#!/usr/bin/env python3
"""Install a verified local build without merging it into an older app bundle."""
import argparse
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile


BUNDLE_ID = "dev.ash.terminal"


def check_identity(app):
    if app.is_symlink() or not app.is_dir():
        raise ValueError(f"Not an application directory: {app}")
    with (app / "Contents/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    if info.get("CFBundleIdentifier") != BUNDLE_ID:
        raise ValueError(f"Refusing to replace an unrelated application: {app}")
    if info.get("CFBundleExecutable") != "Ash" or not (app / "Contents/MacOS/Ash").is_file():
        raise ValueError(f"Incomplete Ash application: {app}")


def install_app(source, applications=Path("/Applications")):
    source = Path(source).absolute()
    applications = Path(applications).resolve(strict=True)
    target = applications / "Ash.app"
    check_identity(source)
    if source.resolve() == target.resolve():
        raise ValueError("The source is already the installed application.")
    if target.exists() or target.is_symlink():
        check_identity(target)

    # Stage on the destination filesystem so activation uses directory renames.
    staging = Path(tempfile.mkdtemp(prefix=".ash-install-", dir=applications))
    candidate = staging / "Ash.app"
    previous = staging / "previous.app"
    try:
        subprocess.run(["/usr/bin/ditto", str(source), str(candidate)], check=True)
        check_identity(candidate)
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(candidate)], check=True)
        if target.exists():
            os.replace(target, previous)
        try:
            os.replace(candidate, target)
        except BaseException:
            if previous.exists():
                os.replace(previous, target)
            raise
    finally:
        # If restoring the old application itself failed, preserve the backup for recovery.
        if previous.exists() and not target.exists():
            print(f"Previous application preserved at {previous}")
        else:
            shutil.rmtree(staging)
    return target


def main():
    parser = argparse.ArgumentParser(description="Install a signed Ash build in Applications.")
    parser.add_argument("source", nargs="?", type=Path,
                        default=Path(__file__).resolve().parents[1] / "dist/Ash.app")
    args = parser.parse_args()
    try:
        target = install_app(args.source)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.exit(1, f"Ash installation failed: {error}\nBuild retained at {args.source}\n")
    print(f"Installed {target}")


if __name__ == "__main__":
    main()
