#!/usr/bin/env python3
"""Exercise installation and rollback in temporary directories, never /Applications."""
import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("install_app", ROOT / "scripts/install-app.py")
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


class InstallationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="ash-install-app-")
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name).resolve()
        self.source = root / "build/Ash.app"
        contents = self.source / "Contents"
        (contents / "MacOS").mkdir(parents=True)
        (contents / "Info.plist").write_bytes(plistlib.dumps({
            "CFBundleIdentifier": installer.BUNDLE_ID, "CFBundleExecutable": "Ash",
            "CFBundleName": "Ash", "CFBundlePackageType": "APPL",
        }))
        shutil.copy("/usr/bin/true", contents / "MacOS/Ash")
        subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", str(self.source)],
                       check=True, capture_output=True)
        self.applications = root / "Applications"
        self.applications.mkdir()
        self.target = self.applications / "Ash.app"

    def previous_app(self):
        shutil.copytree(self.source, self.target)
        (self.target / "previous-marker").write_text("old app")

    def test_first_install_and_update_replace_entire_bundle(self):
        self.assertEqual(installer.install_app(self.source, self.applications), self.target)
        (self.target / "stale-file").write_text("must not survive an update")
        installer.install_app(self.source, self.applications)
        self.assertFalse((self.target / "stale-file").exists())
        self.assertTrue(self.source.exists())
        self.assertEqual(list(self.applications.iterdir()), [self.target])

    def test_invalid_signature_preserves_previous_app(self):
        self.previous_app()
        with (self.source / "Contents/MacOS/Ash").open("ab") as file:
            file.write(b"tampered")
        with self.assertRaises(subprocess.CalledProcessError):
            installer.install_app(self.source, self.applications)
        self.assertEqual((self.target / "previous-marker").read_text(), "old app")
        self.assertEqual(list(self.applications.iterdir()), [self.target])

    def test_failed_activation_restores_previous_app(self):
        self.previous_app()
        replace = os.replace

        def fail_candidate(source, destination):
            if Path(source).name == "Ash.app" and Path(source).parent.name.startswith(".ash-install-"):
                raise OSError("simulated activation failure")
            return replace(source, destination)

        with patch.object(installer.os, "replace", side_effect=fail_candidate):
            with self.assertRaisesRegex(OSError, "simulated activation failure"):
                installer.install_app(self.source, self.applications)
        self.assertEqual((self.target / "previous-marker").read_text(), "old app")
        self.assertEqual(list(self.applications.iterdir()), [self.target])

    def test_unrelated_application_is_not_replaced(self):
        self.previous_app()
        plist = self.target / "Contents/Info.plist"
        info = plistlib.loads(plist.read_bytes())
        info["CFBundleIdentifier"] = "example.unrelated"
        plist.write_bytes(plistlib.dumps(info))
        with self.assertRaisesRegex(ValueError, "unrelated"):
            installer.install_app(self.source, self.applications)
        self.assertTrue((self.target / "previous-marker").exists())


if __name__ == "__main__":
    unittest.main()
