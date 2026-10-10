#!/usr/bin/env python3
"""Prepare a matched stable cask update; never commit or publish it."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import tarfile
import tempfile
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
MAIN = "fcitx/fcitx5-macos"
PLUGINS = "fcitx-contrib/fcitx5-plugins"
VERSION = r"\d+\.\d+\.\d+"


class NotReady(Exception):
    pass


def release(repo, ref):
    headers = {"Accept": "application/vnd.github+json", "User-Agent": "homebrew-fcitx5-updater"}
    if token := os.environ.get("GH_TOKEN"):
        headers["Authorization"] = f"Bearer {token}"
    request = Request(f"https://api.github.com/repos/{repo}/releases/{ref}", headers=headers)
    try:
        with urlopen(request, timeout=60) as response:
            result = json.load(response)
    except HTTPError as error:
        if error.code == 404:
            raise NotReady(f"Release not available: {repo}/{ref}") from error
        raise
    if result.get("draft") or result.get("prerelease"):
        raise NotReady(f"Release is not stable: {repo}/{ref}")
    return result


def asset_metadata(release_data, name):
    assets = [a for a in release_data["assets"] if a["name"] == name and a.get("state") == "uploaded"]
    if len(assets) != 1:
        raise NotReady(f"Expected one uploaded asset: {name}")
    return assets[0]


def download(repo, tag, asset, directory):
    name = asset["name"]
    url = f"https://github.com/{repo}/releases/download/{tag}/{name}"
    path = directory / name
    digest = hashlib.sha256()
    size = 0
    with urlopen(Request(url, headers={"User-Agent": "homebrew-fcitx5-updater"}), timeout=120) as response:
        with path.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                size += len(chunk)
                if size > 1024 * 1024 * 1024:
                    raise ValueError(f"Unexpectedly large asset: {name}")
                digest.update(chunk)
                output.write(chunk)
    checksum = digest.hexdigest()
    if size != asset["size"]:
        raise ValueError(f"Download size mismatch: {name}")
    if asset.get("digest") and asset["digest"] != f"sha256:{checksum}":
        raise ValueError(f"GitHub digest mismatch: {name}")
    return path, checksum


def member(archive, name):
    matches = [m for m in archive.getmembers() if m.name.removeprefix("./") == name]
    if len(matches) != 1 or not matches[0].isfile():
        raise ValueError(f"Expected one regular archive member: {name}")
    return matches[0]


def validate_archive(path, version, name):
    with tarfile.open(path, "r:bz2") as archive:
        if name.startswith("Fcitx5-"):
            info = member(archive, "Fcitx5.app/Contents/Info.plist")
            if info.size > 1024 * 1024:
                raise ValueError("Unexpectedly large Info.plist")
            metadata = plistlib.loads(archive.extractfile(info).read())
            if (metadata.get("CFBundleShortVersionString") != version
                    or str(metadata.get("CFBundleVersion")) != "0"
                    or metadata.get("CFBundleIdentifier") != "org.fcitx.inputmethod.Fcitx5"):
                raise ValueError("Application identity/version/build changed; manual review required")
            minimum = metadata.get("LSMinimumSystemVersion", "13.3")
            if tuple(map(int, minimum.split("."))) > (13, 3, 0):
                raise ValueError("Minimum macOS changed; update installation requirements manually")
            for item in ["MacOS/Fcitx5", "Resources/menu_icon_15.pdf", "Resources/menu_icon_26.pdf"]:
                member(archive, f"Fcitx5.app/Contents/{item}")
        elif name == "rime-any.tar.bz2":
            for item in ["share/fcitx5/addon/rime.conf", "share/fcitx5/inputmethod/rime.conf",
                         "share/rime-data/fcitx5.yaml"]:
                member(archive, item)
        else:
            member(archive, "lib/fcitx5/librime.so")


def replace_once(pattern, replacement, text):
    result, count = re.subn(pattern, lambda match: replacement(match), text, flags=re.MULTILINE)
    if count != 1:
        raise ValueError(f"Package layout changed ({count} matches): {pattern}")
    return result


def rewrite(cask, rime, old, new, sums):
    for label, value in [("old", old), ("new", new)]:
        if not re.fullmatch(VERSION, value):
            raise ValueError(f"Invalid {label} stable version")
    def update_native(text, asset_prefix):
        text = replace_once(r'^  version "' + re.escape(old) + r'"$', lambda _: f'  version "{new}"', text)
        for arch, name in [("arm", "arm64"), ("intel", "x86_64")]:
            pattern = r'^(\s*(?:sha256 )?' + arch + r':\s+")[a-f0-9]{64}("[,]?)$'
            text = replace_once(pattern, lambda m: m[1] + sums[f"{asset_prefix}-{name}.tar.bz2"] + m[2], text)
        return text
    cask = update_native(cask, "Fcitx5")
    rime = update_native(rime, "rime")
    rime = replace_once(r'^(    data_sha256=")[a-f0-9]{64}(")$',
                        lambda m: m[1] + sums["rime-any.tar.bz2"] + m[2], rime)
    return cask, rime


def prepare(root=ROOT):
    cask_path = root / "Casks/fcitx5-macos.rb"
    rime_path = root / "Casks/fcitx5-macos-rime.rb"
    cask, rime = cask_path.read_text(), rime_path.read_text()
    old = re.search(r'^  version "(' + VERSION + r')"$', cask, re.MULTILINE).group(1)
    latest = release(MAIN, "latest")
    new = latest["tag_name"]
    if not re.fullmatch(VERSION, new):
        raise ValueError(f"Unsupported stable tag: {new}")
    if tuple(map(int, new.split("."))) <= tuple(map(int, old.split("."))):
        return False, f"Already at {old}; upstream latest is {new}."
    plugins = release(PLUGINS, f"tags/macos-{new}")
    if plugins["tag_name"] != f"macos-{new}":
        raise ValueError("Plugin release tag mismatch")
    inputs = [(MAIN, new, latest, f"Fcitx5-{a}.tar.bz2") for a in ["arm64", "x86_64"]]
    inputs += [(PLUGINS, f"macos-{new}", plugins, f"rime-{a}.tar.bz2") for a in ["arm64", "x86_64", "any"]]
    assets = [(repo, tag, asset_metadata(data, name)) for repo, tag, data, name in inputs]
    sums = {}
    with tempfile.TemporaryDirectory(prefix="fcitx5-release-") as directory:
        for repo, tag, asset in assets:
            path, checksum = download(repo, tag, asset, Path(directory))
            validate_archive(path, new, asset["name"])
            sums[asset["name"]] = checksum
    new_cask, new_rime = rewrite(cask, rime, old, new, sums)
    cask_path.write_text(new_cask)
    rime_path.write_text(new_rime)
    report = (f"Update Fcitx5 macOS and its matching Rime plugin from {old} to {new}.\n\n"
              f"- [Main release](https://github.com/{MAIN}/releases/tag/{new})\n"
              f"- [Plugin release](https://github.com/{PLUGINS}/releases/tag/macos-{new})\n\n"
              "Downloaded all five assets, checked sizes and available GitHub digests, "
              "validated archive layout and stable application identity/version, and computed SHA-256.\n\n"
              "| Asset | SHA-256 |\n| --- | --- |\n"
              + "".join(f"| {name} | `{checksum}` |\n" for name, checksum in sums.items())
              + "\nReview upstream compatibility and perform installation, upgrade and input tests before merging. "
              "This workflow does not install upstream binaries or test actual input.\n")
    return True, report


def main():
    try:
        changed, report = prepare()
    except NotReady as error:
        changed, report = False, f"Waiting for matching stable release assets: {error}"
    print(report)
    if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
        with open(summary, "a") as stream:
            stream.write(report + "\n")
    if changed:
        Path(os.environ.get("RUNNER_TEMP", tempfile.gettempdir()), "fcitx5-upgrade-pr.md").write_text(report)
    if output := os.environ.get("GITHUB_OUTPUT"):
        with open(output, "a") as stream:
            stream.write(f"changed={str(changed).lower()}\n")


if __name__ == "__main__":
    main()
