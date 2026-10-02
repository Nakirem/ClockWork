"""Tests for the AltStore Classic source updater, using synthetic data only."""
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from update_altstore_source import build_download_url, main, make_version_entry, read_app_info, update_source


def sample_source():
    return {
        "name": "ClockWork",
        "identifier": "com.personal.ClockWork.source",
        "apps": [
            {
                "name": "ClockWork",
                "bundleIdentifier": "com.personal.ClockWork",
                "developerName": "Nakirem",
                "localizedDescription": "Pointage personnel.",
                "iconURL": "https://example.com/icon.png",
                "versions": [
                    {"version": "1.0", "date": "2026-10-02T00:00:00Z",
                     "downloadURL": "https://example.com/old.ipa", "size": 10}
                ]
            }
        ]
    }


class UpdateSourceTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)

    def write_source(self, source):
        path = self.root / "apps.json"
        path.write_text(json.dumps(source, indent=2), encoding="utf-8")
        return path

    def write_info(self, values):
        path = self.root / "Info.plist"
        path.write_bytes(plistlib.dumps(values, fmt=plistlib.FMT_BINARY))
        return path

    def write_ipa(self, size):
        path = self.root / "ClockWork-unsigned.ipa"
        path.write_bytes(b"x" * size)
        return path

    def test_build_download_url_with_simple_tag(self):
        self.assertEqual(
            build_download_url("Nakirem/ClockWork", "v1.0.0", "ClockWork-unsigned.ipa"),
            "https://github.com/Nakirem/ClockWork/releases/download/v1.0.0/ClockWork-unsigned.ipa")

    def test_build_download_url_quotes_special_characters(self):
        self.assertEqual(
            build_download_url("Nakirem/ClockWork", "v1.0 beta", "My App.ipa"),
            "https://github.com/Nakirem/ClockWork/releases/download/v1.0%20beta/My%20App.ipa")

    def test_update_source_inserts_new_version_first(self):
        entry = make_version_entry("1.1", "2026-10-03T00:00:00Z", "https://example.com/new.ipa", 42, "17.0", None)
        updated = update_source(sample_source(), "com.personal.ClockWork", entry)
        self.assertEqual(updated["apps"][0]["versions"][0]["version"], "1.1")
        self.assertEqual(updated["apps"][0]["versions"][1]["version"], "1.0")

    def test_update_source_replaces_entry_with_same_version(self):
        entry = make_version_entry("1.0", "2026-10-03T00:00:00Z", "https://example.com/new.ipa", 42, "17.0", None)
        updated = update_source(sample_source(), "com.personal.ClockWork", entry)
        self.assertEqual(len(updated["apps"][0]["versions"]), 1)
        self.assertEqual(updated["apps"][0]["versions"][0]["size"], 42)

    def test_update_source_keeps_older_versions(self):
        source = sample_source()
        source["apps"][0]["versions"].append(
            {"version": "0.9", "date": "2026-09-01T00:00:00Z",
             "downloadURL": "https://example.com/older.ipa", "size": 8})
        entry = make_version_entry("1.1", "2026-10-03T00:00:00Z", "https://example.com/new.ipa", 42, None, None)
        updated = update_source(source, "com.personal.ClockWork", entry)
        self.assertEqual([v["version"] for v in updated["apps"][0]["versions"]], ["1.1", "1.0", "0.9"])

    def test_update_source_does_not_mutate_input(self):
        source = sample_source()
        entry = make_version_entry("1.1", "2026-10-03T00:00:00Z", "https://example.com/new.ipa", 42, None, None)
        update_source(source, "com.personal.ClockWork", entry)
        self.assertEqual(source["apps"][0]["versions"][0]["version"], "1.0")
        self.assertEqual(len(source["apps"][0]["versions"]), 1)

    def test_update_source_raises_when_bundle_identifier_missing(self):
        entry = make_version_entry("1.1", "2026-10-03T00:00:00Z", "https://example.com/new.ipa", 42, None, None)
        with self.assertRaisesRegex(ValueError, "App not found"):
            update_source(sample_source(), "com.other.App", entry)

    def test_read_app_info_returns_version_and_min_os(self):
        path = self.write_info({"CFBundleShortVersionString": "1.2", "MinimumOSVersion": "17.0"})
        self.assertEqual(read_app_info(path), {"version": "1.2", "minOSVersion": "17.0"})

    def test_read_app_info_rejects_unresolved_version(self):
        path = self.write_info({"CFBundleShortVersionString": "$(MARKETING_VERSION)"})
        with self.assertRaisesRegex(ValueError, "unresolved"):
            read_app_info(path)

    def test_main_updates_source_end_to_end(self):
        source_path = self.write_source(sample_source())
        info_path = self.write_info({"CFBundleShortVersionString": "1.1", "MinimumOSVersion": "17.0"})
        ipa_path = self.write_ipa(1234)
        code = main(["--source", str(source_path), "--info", str(info_path), "--ipa", str(ipa_path),
                     "--tag", "v1.1.0", "--repo", "Nakirem/ClockWork", "--date", "2026-10-03T12:00:00Z"])
        self.assertEqual(code, 0)
        with source_path.open(encoding="utf-8") as handle:
            written = json.load(handle)
        first = written["apps"][0]["versions"][0]
        self.assertEqual(first["version"], "1.1")
        self.assertEqual(first["size"], 1234)
        self.assertEqual(first["date"], "2026-10-03T12:00:00Z")
        self.assertEqual(first["minOSVersion"], "17.0")
        self.assertEqual(first["downloadURL"],
                         "https://github.com/Nakirem/ClockWork/releases/download/v1.1.0/ClockWork-unsigned.ipa")


if __name__ == "__main__":
    unittest.main()
