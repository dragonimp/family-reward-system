#!/usr/bin/env python3
"""Check final distribution signatures, including Apple's watch-only container stub."""
import plistlib
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("Usage: verify-ipa.py HappyLife.ipa")
with tempfile.TemporaryDirectory(prefix="happylife-ipa-check-") as directory:
    with zipfile.ZipFile(sys.argv[1]) as archive:
        archive.extractall(directory)
    container = Path(directory) / "Payload/HappyLife.app"
    watch = container / "Watch/HappyLifeWatch.app"
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(container)], check=True)
    versions = []
    for app, expected in [(container, "net.impx.happylife.watch.apple"),
                          (watch, "net.impx.happylife.watch.apple.watchkitapp")]:
        info = plistlib.loads((app / "Info.plist").read_bytes())
        signature = subprocess.run(["codesign", "-dv", str(app)], capture_output=True, text=True, check=True)
        fields = dict(line.split("=", 1) for line in signature.stderr.splitlines() if "=" in line)
        assert info["CFBundleIdentifier"] == expected
        assert fields["Identifier"] == expected, "Code signature identifier differs from Bundle ID"
        assert fields["TeamIdentifier"] == "JQPH54K7SD"
        signed_entitlements = subprocess.run(["codesign", "-d", "--entitlements", ":-", str(app)],
                                             capture_output=True, check=True)
        entitlements = plistlib.loads(signed_entitlements.stdout)
        assert entitlements["application-identifier"] == "JQPH54K7SD." + expected
        assert entitlements.get("get-task-allow") is False, "Distribution build must not allow debugging"
        assert (app / "embedded.mobileprovision").is_file(), "Distribution profile is missing"
        versions.append((info["CFBundleShortVersionString"], info["CFBundleVersion"]))
    assert versions[0] == versions[1], "Container and watch versions differ"
    info = plistlib.loads((watch / "Info.plist").read_bytes())
    assert info["WKWatchOnly"] and "WKRunsIndependentlyOfCompanionApp" not in info
    assert (watch / "Assets.car").is_file(), "Compiled watch assets are missing"
    print(f"PASS: distribution signatures, Bundle IDs, profiles, watch-only mode, assets and version {versions[0]}")
