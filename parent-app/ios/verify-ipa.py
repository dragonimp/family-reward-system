#!/usr/bin/env python3
"""Validate the exported parent app independently of Xcode's export result."""
import datetime
import hashlib
import plistlib
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("Usage: verify-ipa.py Linko-Family.ipa")
ipa = Path(sys.argv[1])
with tempfile.TemporaryDirectory(prefix="happylife-parent-ipa-") as directory:
    with zipfile.ZipFile(ipa) as archive:
        archive.extractall(directory)
    app = Path(directory) / "Payload/Linko-Family.app"
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    info = plistlib.loads((app / "Info.plist").read_bytes())
    expected = "net.impx.happylife.parent"
    signature = subprocess.run(["codesign", "-dv", str(app)], capture_output=True, text=True, check=True)
    fields = dict(line.split("=", 1) for line in signature.stderr.splitlines() if "=" in line)
    assert info["CFBundleIdentifier"] == expected
    assert info["CFBundleDisplayName"] == "Linko-Family"
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
    profile = plistlib.loads(subprocess.run(
        ["security", "cms", "-D", "-i", str(app / "embedded.mobileprovision")],
        capture_output=True, check=True).stdout)
    assert profile["TeamIdentifier"] == ["JQPH54K7SD"]
    assert profile["Entitlements"]["application-identifier"] == entitlements["application-identifier"]
    assert profile["ExpirationDate"].replace(tzinfo=datetime.timezone.utc) > datetime.datetime.now(datetime.timezone.utc)
    assert not profile.get("ProvisionedDevices") and not profile.get("ProvisionsAllDevices")
    assert (app / "Assets.car").is_file()
    assert info["CFBundleIcons"]["CFBundlePrimaryIcon"]["CFBundleIconName"] == "AppIcon"
    print("PASS:", expected, info["CFBundleShortVersionString"], info["CFBundleVersion"], "App Store signature/profile/icon/native frameworks/callback")
    print("SHA256:", hashlib.sha256(ipa.read_bytes()).hexdigest())
