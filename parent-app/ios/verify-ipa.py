#!/usr/bin/env python3
"""Validate the exported parent app independently of Xcode's export result."""
import datetime
import hashlib
import os
import plistlib
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("Usage: verify-ipa.py Linko Moment.ipa")
ipa = Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix="happylife-parent-ipa-") as directory:
    with zipfile.ZipFile(ipa) as archive:
        archive.extractall(directory)
    app = Path(directory) / "Payload/Linko Moment.app"
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    info = plistlib.loads((app / "Info.plist").read_bytes())
    flavor = os.environ.get('MOMENT_IOS_RELEASE_FLAVOR', 'successor')
    assert flavor in ('legacy', 'successor')
    expected = 'net.impx.happylife.parent' if flavor == 'legacy' else 'net.impx.happylife'
    english_name = 'LinkoXMoment' if flavor == 'legacy' else 'Linko Moment'
    chinese_name = 'LinkoXMoment' if flavor == 'legacy' else '灵可时刻'
    group = 'group.' + expected
    signature = subprocess.run(["codesign", "-dv", str(app)], capture_output=True, text=True, check=True)
    fields = dict(line.split("=", 1) for line in signature.stderr.splitlines() if "=" in line)
    assert info["CFBundleIdentifier"] == expected
    assert info["CFBundleDisplayName"] == english_name
    for locale,name in [('en',english_name),('zh-Hans',chinese_name)]:
        assert plistlib.loads((app/(locale+'.lproj')/'InfoPlist.strings').read_bytes())['CFBundleDisplayName'] == name
    assert any("linkofamily" in item.get("CFBundleURLSchemes", []) for item in info.get("CFBundleURLTypes", []))
    frameworks = subprocess.run(["xcrun", "otool", "-L", str(app / info["CFBundleExecutable"])], capture_output=True, text=True, check=True).stdout
    assert "SwiftUI.framework" in frameworks and "AuthenticationServices.framework" in frameworks
    assert "WebKit.framework" not in frameworks
    assert fields["Identifier"] == expected
    assert fields["TeamIdentifier"] == "JQPH54K7SD"
    entitlements = plistlib.loads(subprocess.run(
        ["codesign", "-d", "--entitlements", ":-", str(app)], capture_output=True, check=True).stdout)
    assert entitlements["application-identifier"] == "JQPH54K7SD." + expected
    assert entitlements.get("get-task-allow") is False
    assert entitlements.get("aps-environment") == "production"
    assert group in entitlements.get("com.apple.security.application-groups", [])
    profile = plistlib.loads(subprocess.run(
        ["security", "cms", "-D", "-i", str(app / "embedded.mobileprovision")],
        capture_output=True, check=True).stdout)
    assert profile["TeamIdentifier"] == ["JQPH54K7SD"]
    assert profile["Entitlements"]["application-identifier"] == entitlements["application-identifier"]
    assert profile["Entitlements"].get("aps-environment") == "production"
    assert group in profile["Entitlements"].get("com.apple.security.application-groups", [])
    assert profile["ExpirationDate"].replace(tzinfo=datetime.timezone.utc) > datetime.datetime.now(datetime.timezone.utc)
    assert not profile.get("ProvisionedDevices") and not profile.get("ProvisionsAllDevices")
    assert (app / "Assets.car").is_file()
    assert info["CFBundleIcons"]["CFBundlePrimaryIcon"]["CFBundleIconName"] == "AppIcon"
    watch = app / "Watch/Linko Moment Watch.app"
    wi = plistlib.loads((watch / "Info.plist").read_bytes())
    assert wi["CFBundleIdentifier"] == expected + ".watchkitapp"
    assert wi["WKCompanionAppBundleIdentifier"] == expected
    assert wi["WKRunsIndependentlyOfCompanionApp"] is True
    assert wi.get("WKWatchOnly") is not True
    assert wi["CFBundleDisplayName"] == english_name
    assert plistlib.loads((watch/'zh-Hans.lproj/InfoPlist.strings').read_bytes())['CFBundleDisplayName'] == chinese_name
    assert wi["CFBundleShortVersionString"] == info["CFBundleShortVersionString"]
    assert wi["CFBundleVersion"] == info["CFBundleVersion"]
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(watch)], check=True)
    we = plistlib.loads(subprocess.run(["codesign", "-d", "--entitlements", ":-", str(watch)], capture_output=True, check=True).stdout)
    assert we["application-identifier"] == "JQPH54K7SD." + wi["CFBundleIdentifier"]
    assert we.get("get-task-allow") is False
    wp = plistlib.loads(subprocess.run(["security", "cms", "-D", "-i", str(watch / "embedded.mobileprovision")], capture_output=True, check=True).stdout)
    assert wp["Entitlements"]["application-identifier"] == we["application-identifier"]
    assert wp["ExpirationDate"].replace(tzinfo=datetime.timezone.utc) > datetime.datetime.now(datetime.timezone.utc)
    assert not wp.get("ProvisionedDevices") and not wp.get("ProvisionsAllDevices")
    assert (watch / "Assets.car").is_file()
    share = app / "PlugIns/Linko Moment Share.appex"
    si = plistlib.loads((share / "Info.plist").read_bytes())
    assert si["CFBundleIdentifier"] == expected + ".share"
    assert si["CFBundleShortVersionString"] == info["CFBundleShortVersionString"]
    assert si["CFBundleVersion"] == info["CFBundleVersion"]
    assert si["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.share-services"
    subprocess.run(["codesign", "--verify", "--strict", str(share)], check=True)
    se = plistlib.loads(subprocess.run(["codesign", "-d", "--entitlements", ":-", str(share)], capture_output=True, check=True).stdout)
    assert se["application-identifier"] == "JQPH54K7SD." + expected + ".share"
    assert group in se.get("com.apple.security.application-groups", [])
    sp = plistlib.loads(subprocess.run(["security", "cms", "-D", "-i", str(share / "embedded.mobileprovision")], capture_output=True, check=True).stdout)
    assert sp["Entitlements"]["application-identifier"] == se["application-identifier"]
    assert group in sp["Entitlements"].get("com.apple.security.application-groups", [])
    print("PASS: embedded Watch app, independent companion configuration, matching versions and distribution profile")
    print("PASS:", expected, info["CFBundleShortVersionString"], info["CFBundleVersion"], "App Store signature/profile/icon/native frameworks/callback")
    print("SHA256:", hashlib.sha256(ipa.read_bytes()).hexdigest())
