"""Package an Xcode-built iPhone .app for re-signing with Sideloadly.

This does not compile or sign an app. A simulator build is explicitly rejected.
Uses only Python's standard library and never modifies the input application.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import stat
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED


def package(app: Path, output: Path) -> Path:
    app = app.resolve()
    output = output.resolve()
    if not app.is_dir() or app.suffix != ".app":
        raise ValueError("Expected an existing Xcode-built .app directory")
    if output.suffix != ".ipa" or output.is_relative_to(app):
        raise ValueError("Output must be an .ipa outside the input application")
    if output.exists():
        raise ValueError("Output already exists; choose a new output path")
    with (app / "Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    if info.get("DTPlatformName") != "iphoneos" or "iPhoneOS" not in info.get("CFBundleSupportedPlatforms", []):
        raise ValueError("Only an iPhone device build is accepted, never a simulator build")
    executable = info.get("CFBundleExecutable", "")
    if not executable or Path(executable).name != executable or not (app / executable).is_file():
        raise ValueError("Missing or invalid application executable")
    if not info.get("CFBundleIdentifier") or "$" in info["CFBundleIdentifier"]:
        raise ValueError("Missing or unresolved bundle identifier")
    # Inspect all paths before writing any output. Preserve safe framework symlinks.
    files = sorted(path for path in app.rglob("*") if path.is_file() or path.is_symlink())
    for path in files:
        if path.is_symlink() and not path.resolve().is_relative_to(app):
            raise ValueError("A symlink points outside the application")
    output.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(output, "x", compression=ZIP_DEFLATED) as archive:
        for path in files:
            if path.name == ".DS_Store":
                continue
            name = "Payload/" + app.name + "/" + path.relative_to(app).as_posix()
            if path.is_symlink():
                entry = ZipInfo(name)
                entry.create_system = 3
                entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                archive.writestr(entry, os.readlink(path).encode("utf-8"))
            else:
                entry = ZipInfo.from_file(path, arcname=name)
                entry.create_system = 3
                mode = path.stat().st_mode
                if path == app / executable:
                    mode |= 0o111
                entry.external_attr = mode << 16
                archive.writestr(entry, path.read_bytes(), compress_type=ZIP_DEFLATED)
    with ZipFile(output) as archive:
        if archive.testzip() is not None:
            raise ValueError("Generated archive failed CRC verification")
        assert f"Payload/{app.name}/{executable}" in archive.namelist()
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    output.with_suffix(".ipa.sha256").write_text(f"{digest}  {output.name}\n", encoding="utf-8")
    metadata = {
        "bundle_identifier": info["CFBundleIdentifier"],
        "version": info.get("CFBundleShortVersionString"),
        "build": info.get("CFBundleVersion"),
        "minimum_ios": info.get("MinimumOSVersion"),
        "platform": "iphoneos",
        "signing": "Must be re-signed by Sideloadly before installation",
        "commit": os.environ.get("GITHUB_SHA"),
        "sha256": digest,
    }
    output.with_suffix(".json").write_text(json.dumps(metadata, indent=2) + "\n", encoding="utf-8")
    return output


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    print(f"Packaged for Sideloadly: {package(args.app, args.output)}")
