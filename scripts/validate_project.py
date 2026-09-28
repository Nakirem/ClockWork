"""Portable structural checks. These do NOT replace Swift compilation or XCTest."""
from pathlib import Path
import json
import plistlib
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
project = (root / "ClockWork.xcodeproj/project.pbxproj").read_text(encoding="utf-8")
definitions = re.findall(r"^\s*([A-F0-9]{24}) =", project, re.M)
assert len(definitions) == len(set(definitions)), "Duplicate PBX identifiers"
references = set(re.findall(r"\b[A-F0-9]{24}\b", project))
assert references == set(definitions), "Unresolved PBX references"
for path in re.findall(r'path = "([^"]+)";', project):
    assert (root / path).exists(), f"Missing file: {path}"
for path in (root / "ClockWork").rglob("*.swift"):
    assert path.relative_to(root).as_posix() in project, f"Source not in app: {path}"
for path in (root / "Tests").rglob("*.swift"):
    assert path.relative_to(root).as_posix() in project, f"Source not in tests: {path}"
for path in list(root.rglob("*.plist")) + list(root.rglob("*.xcprivacy")):
    with path.open("rb") as file: plistlib.load(file)
for path in (root / "ClockWork/Resources").rglob("*.json"):
    json.loads(path.read_text())
ET.parse(root / "ClockWork.xcodeproj/xcshareddata/xcschemes/ClockWork.xcscheme")
ET.parse(root / "ClockWork.xcodeproj/project.xcworkspace/contents.xcworkspacedata")
with (root / "ClockWork/Resources/Info.plist").open("rb") as file:
    info = plistlib.load(file)
assert info["NSLocationWhenInUseUsageDescription"]
assert info["NSLocationAlwaysAndWhenInUseUsageDescription"]
assert "location" not in info.get("UIBackgroundModes", []), "Continuous GPS not used"
test_count = sum(len(re.findall(r"func test\w+\(", p.read_text(encoding="utf-8"))) for p in (root / "Tests").rglob("*.swift"))
print(f"PASS: project references, sources, plist, privacy manifest, assets, scheme. {test_count} XCTest methods present (not executed).")
