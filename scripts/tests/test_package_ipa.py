"""Tests only ZIP packaging, using fake bytes; does not produce an installable app."""
import hashlib
from pathlib import Path
import plistlib
import stat
import sys
import tempfile
import unittest
from zipfile import ZipFile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from package_ipa import package


class PackageTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "ClockWork.app"
        self.app.mkdir()
        (self.app / "ClockWork").write_bytes(b"FAKE TEST EXECUTABLE - NOT AN IOS APPLICATION")
        (self.app / "Assets.car").write_bytes(b"fake assets")
        self.info = {"DTPlatformName": "iphoneos", "CFBundleSupportedPlatforms": ["iPhoneOS"],
                     "CFBundleIdentifier": "com.personal.ClockWork", "CFBundleExecutable": "ClockWork"}
        self.write_info()
        self.output = self.root / "output" / "test-only.ipa"

    def write_info(self):
        (self.app / "Info.plist").write_bytes(plistlib.dumps(self.info, fmt=plistlib.FMT_BINARY))

    def test_payload_resources_permissions_and_checksum(self):
        package(self.app, self.output)
        with ZipFile(self.output) as archive:
            self.assertEqual(set(archive.namelist()), {"Payload/ClockWork.app/Info.plist", "Payload/ClockWork.app/ClockWork", "Payload/ClockWork.app/Assets.car"})
            mode = archive.getinfo("Payload/ClockWork.app/ClockWork").external_attr >> 16
            self.assertTrue(mode & stat.S_IXUSR)
            self.assertEqual(archive.read("Payload/ClockWork.app/ClockWork"), (self.app / "ClockWork").read_bytes())
        digest = hashlib.sha256(self.output.read_bytes()).hexdigest()
        self.assertEqual(self.output.with_suffix(".ipa.sha256").read_text().split()[0], digest)

    def test_reject_simulator_even_if_architecture_could_be_arm64(self):
        self.info["DTPlatformName"] = "iphonesimulator"
        self.info["CFBundleSupportedPlatforms"] = ["iPhoneSimulator"]
        self.write_info()
        with self.assertRaisesRegex(ValueError, "device build"):
            package(self.app, self.output)
        self.assertFalse(self.output.exists())

    def test_reject_missing_executable(self):
        self.info["CFBundleExecutable"] = "Missing"
        self.write_info()
        with self.assertRaisesRegex(ValueError, "executable"):
            package(self.app, self.output)

    def test_reject_output_inside_input(self):
        with self.assertRaisesRegex(ValueError, "outside"):
            package(self.app, self.app / "recursive.ipa")

    def test_never_overwrite_existing_ipa(self):
        package(self.app, self.output)
        original = self.output.read_bytes()
        with self.assertRaisesRegex(ValueError, "already exists"):
            package(self.app, self.output)
        self.assertEqual(self.output.read_bytes(), original)

    def test_reject_unprocessed_xcode_bundle_identifier(self):
        self.info["CFBundleIdentifier"] = "$(PRODUCT_BUNDLE_IDENTIFIER)"
        self.write_info()
        with self.assertRaisesRegex(ValueError, "bundle identifier"):
            package(self.app, self.output)


if __name__ == "__main__":
    unittest.main()
