"""Update the AltStore Classic source (apps.json) with a freshly built release.

Schema verified against AltStore Classic v1.6.3 (altstoreio/AltStore):
- versions[0] is the latest version; AltStore compares the "version" string
  (CFBundleShortVersionString) with the installed app.
- Required fields: version, date (ISO-8601), downloadURL, size (bytes).
- Optional: localizedDescription, minOSVersion, maxOSVersion.

Uses only Python's standard library and never modifies files other than the source JSON.
"""
import argparse
import copy
import datetime
import json
import logging
import plistlib
import urllib.parse
from pathlib import Path
from typing import Any

log = logging.getLogger(__name__)

DEFAULT_BUNDLE_ID = "com.personal.ClockWork"
DEFAULT_ASSET_NAME = "ClockWork-unsigned.ipa"


def build_download_url(repo: str, tag: str, asset_name: str) -> str:
    """Return the GitHub release asset URL for the given tag."""
    quoted_tag = urllib.parse.quote(tag, safe="")
    quoted_asset = urllib.parse.quote(asset_name, safe="")
    return f"https://github.com/{repo}/releases/download/{quoted_tag}/{quoted_asset}"


def read_app_info(info_path: Path) -> dict[str, str]:
    """Return {"version": ..., "minOSVersion": ...} from a built Info.plist."""
    with info_path.open("rb") as handle:
        info = plistlib.load(handle)
    version = info.get("CFBundleShortVersionString")
    if not version or "$" in str(version):
        raise ValueError(f"Missing or unresolved CFBundleShortVersionString in {info_path}")
    result: dict[str, str] = {"version": str(version)}
    min_os = info.get("MinimumOSVersion")
    if min_os:
        result["minOSVersion"] = str(min_os)
    return result


def make_version_entry(version: str, date: str, download_url: str, size: int,
                       min_os: str | None, description: str | None) -> dict[str, Any]:
    entry: dict[str, Any] = {"version": version, "date": date, "downloadURL": download_url, "size": size}
    if min_os:
        entry["minOSVersion"] = min_os
    if description:
        entry["localizedDescription"] = description
    return entry


def update_source(source: dict[str, Any], bundle_id: str, entry: dict[str, Any]) -> dict[str, Any]:
    """Return a NEW source dict with entry inserted as versions[0] for the app."""
    updated = copy.deepcopy(source)
    apps = updated.get("apps")
    if not isinstance(apps, list):
        raise ValueError("Invalid source: missing apps array")
    for app in apps:
        if not isinstance(app, dict) or app.get("bundleIdentifier") != bundle_id:
            continue
        versions = [v for v in app.get("versions", [])
                    if isinstance(v, dict) and v.get("version") != entry["version"]]
        app["versions"] = [entry] + versions
        return updated
    raise ValueError(f"App not found in source: {bundle_id}")


def utc_now_iso() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True, help="apps.json AltStore source file")
    parser.add_argument("--info", type=Path, required=True, help="built app Info.plist")
    parser.add_argument("--ipa", type=Path, required=True, help="built IPA file")
    parser.add_argument("--tag", required=True, help="Git tag of the release (e.g. v1.0.0)")
    parser.add_argument("--repo", required=True, help="GitHub repository (e.g. Nakirem/ClockWork)")
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID, help=f"bundle identifier (default: {DEFAULT_BUNDLE_ID})")
    parser.add_argument("--asset-name", default=DEFAULT_ASSET_NAME, help=f"IPA asset name (default: {DEFAULT_ASSET_NAME})")
    parser.add_argument("--date", default=None, help="ISO-8601 publication date (default: now, UTC)")
    parser.add_argument("--description", default=None, help="localizedDescription of this version")
    args = parser.parse_args(argv)
    if not args.ipa.is_file():
        parser.error(f"IPA not found: {args.ipa}")
    app_info = read_app_info(args.info)
    entry = make_version_entry(
        app_info["version"],
        args.date or utc_now_iso(),
        build_download_url(args.repo, args.tag, args.asset_name),
        args.ipa.stat().st_size,
        app_info.get("minOSVersion"),
        args.description,
    )
    with args.source.open(encoding="utf-8") as handle:
        source = json.load(handle)
    updated = update_source(source, args.bundle_id, entry)
    args.source.write_text(json.dumps(updated, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    log.info("Updated %s: %s %s (%d bytes) from %s",
             args.source, args.bundle_id, entry["version"], entry["size"], entry["downloadURL"])
    return 0


if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    raise SystemExit(main())
