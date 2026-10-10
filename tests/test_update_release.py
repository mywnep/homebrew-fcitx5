import importlib.util
import io
import json
from pathlib import Path
import plistlib
import shutil
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("updater", ROOT / "scripts/update_release.py")
u = importlib.util.module_from_spec(spec)
spec.loader.exec_module(u)


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        for directory in ["Casks"]:
            shutil.copytree(ROOT / directory, self.root / directory)
        self.cask = self.root / "Casks/fcitx5-macos.rb"
        self.rime = self.root / "Casks/fcitx5-macos-rime.rb"
        self.before = (self.cask.read_text(), self.rime.read_text())
        self.old = u.re.search(r'^  version "([^"]+)"', self.before[0], u.re.M)[1]
        self.new = f"{int(self.old.split('.')[0]) + 1}.0.0"
        self.assets = [f"Fcitx5-{a}.tar.bz2" for a in ["arm64", "x86_64"]]
        self.assets += [f"rime-{a}.tar.bz2" for a in ["arm64", "x86_64", "any"]]
        self.releases = [self.make_release(self.new, self.assets[:2]),
                         self.make_release(f"macos-{self.new}", self.assets[2:])]

    def make_release(self, tag, names):
        return {"tag_name": tag, "assets": [{"name": n, "state": "uploaded"} for n in names]}

    def unchanged(self):
        self.assertEqual(self.before, (self.cask.read_text(), self.rime.read_text()))

    def fake_download(self, repo, tag, asset, directory):
        return directory / asset["name"], "a" * 64

    def test_matched_update_and_noop(self):
        with patch.object(u, "release", side_effect=self.releases), patch.object(u, "download", side_effect=self.fake_download), patch.object(u, "validate_archive"):
            changed, report = u.prepare(self.root)
        self.assertTrue(changed)
        self.assertIn(self.new, report)
        self.assertIn(f'version "{self.new}"', self.cask.read_text())
        self.assertIn(f'version "{self.new}"', self.rime.read_text())
        self.assertEqual(self.rime.read_text().count('"' + "a" * 64 + '"'), 3)
        self.assertEqual(self.cask.read_text().count('"' + "a" * 64 + '"'), 2)
        with patch.object(u, "release", return_value=self.releases[0]), patch.object(u, "download") as download:
            self.assertFalse(u.prepare(self.root)[0])
            download.assert_not_called()

    def test_missing_plugin_release_leaves_files_untouched(self):
        with patch.object(u, "release", side_effect=[self.releases[0], u.NotReady("missing")]):
            with self.assertRaises(u.NotReady):
                u.prepare(self.root)
        self.unchanged()

    def test_missing_architecture_leaves_files_untouched(self):
        self.releases[1]["assets"].pop()
        with patch.object(u, "release", side_effect=self.releases), patch.object(u, "download") as download:
            with self.assertRaises(u.NotReady):
                u.prepare(self.root)
            download.assert_not_called()
        self.unchanged()

    def test_invalid_archive_leaves_files_untouched(self):
        with patch.object(u, "release", side_effect=self.releases), patch.object(u, "download", side_effect=self.fake_download), patch.object(u, "validate_archive", side_effect=ValueError("bad")):
            with self.assertRaises(ValueError):
                u.prepare(self.root)
        self.unchanged()

    def test_tag_injection_rejected(self):
        self.releases[0]["tag_name"] = '0.5.0"; system("echo bad")'
        with patch.object(u, "release", side_effect=self.releases):
            with self.assertRaises(ValueError):
                u.prepare(self.root)
        self.unchanged()

    def test_layout_change_aborts_both_edits(self):
        self.rime.write_text(u.re.sub(r'^(    data_sha256=")[a-f0-9]{64}',
                                      lambda m: m[0][1:], self.before[1], count=1, flags=u.re.M))
        before = self.rime.read_text()
        with patch.object(u, "release", side_effect=self.releases), patch.object(u, "download", side_effect=self.fake_download), patch.object(u, "validate_archive"):
            with self.assertRaises(ValueError):
                u.prepare(self.root)
        self.assertEqual(self.before[0], self.cask.read_text())
        self.assertEqual(before, self.rime.read_text())

    def test_actual_archive_validation(self):
        path = self.root / "app.tar.bz2"
        metadata = {"CFBundleShortVersionString": self.new, "CFBundleVersion": "0",
                    "CFBundleIdentifier": "org.fcitx.inputmethod.Fcitx5", "LSMinimumSystemVersion": "13.3"}
        def write_archive(build):
            metadata["CFBundleVersion"] = build
            with tarfile.open(path, "w:bz2") as archive:
                files = {"Info.plist": plistlib.dumps(metadata), "MacOS/Fcitx5": b"binary",
                         "Resources/menu_icon_15.pdf": b"icon", "Resources/menu_icon_26.pdf": b"icon"}
                for name, data in files.items():
                    info = tarfile.TarInfo("Fcitx5.app/Contents/" + name)
                    info.size = len(data)
                    archive.addfile(info, io.BytesIO(data))
        write_archive("0")
        u.validate_archive(path, self.new, "Fcitx5-arm64.tar.bz2")
        write_archive("6")
        with self.assertRaises(ValueError):
            u.validate_archive(path, self.new, "Fcitx5-arm64.tar.bz2")

    def test_download_digest_mismatch(self):
        data = b"archive"
        asset = {"name": "Fcitx5-arm64.tar.bz2", "size": len(data), "digest": "sha256:" + "0" * 64}
        with patch.object(u, "urlopen", return_value=io.BytesIO(data)):
            with self.assertRaisesRegex(ValueError, "digest mismatch"):
                u.download(u.MAIN, self.new, asset, self.root)

    def test_prerelease_rejected(self):
        with patch.object(u, "urlopen", return_value=io.BytesIO(json.dumps({"prerelease": True}).encode())):
            with self.assertRaises(u.NotReady):
                u.release(u.MAIN, "latest")


if __name__ == "__main__":
    unittest.main()
