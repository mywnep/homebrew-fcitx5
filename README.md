# Fcitx5 macOS Homebrew tap

English | [简体中文](README.zh-CN.md)

Provides the stable release of [Fcitx5 macOS](Casks/fcitx5-macos.rb) and an optional [Rime plugin](Casks/fcitx5-macos-rime.rb). Supports Apple Silicon and Intel. Requires macOS 13.3 or later and a recent version of Homebrew.

## Installation

Add the tap and install Fcitx5:

```sh
brew tap mywnep/fcitx5
brew trust --cask mywnep/fcitx5/fcitx5-macos
brew install --cask mywnep/fcitx5/fcitx5-macos
```

Fcitx5 is installed at `/Library/Input Methods/Fcitx5.app`. Installation may require an administrator password.

To install Rime:

```sh
brew trust --cask mywnep/fcitx5/fcitx5-macos-rime
brew install --cask mywnep/fcitx5/fcitx5-macos-rime
```

The Rime cask automatically installs Fcitx5 if needed, but does not include input schemas. If you previously installed Fcitx5 or its plugins manually, back up your user data and remove those installations using their original installation method before installing through Homebrew.

## Usage

After installing Fcitx5, log out and back in, then add Fcitx5 in System Settings → Keyboard → Input Sources.

After installing Rime, restart Fcitx5 and add Rime in its input-method configuration. Install a complete schema such as [Wanxiang](https://github.com/amzxyz/rime-wanxiang/releases), along with its required data, and deploy it following the schema's instructions. The default Rime user data directory is `~/.local/share/fcitx5/rime`. If you have changed your environment configuration, open the actual directory from Rime's configuration interface.

Use Homebrew to upgrade Fcitx5 and Rime, keeping their versions matched. Switch to another input source before upgrading, then run these commands in order. Skip the last command if Rime is not installed:

```sh
brew update
brew upgrade --cask --greedy mywnep/fcitx5/fcitx5-macos
brew upgrade --cask mywnep/fcitx5/fcitx5-macos-rime
```

After upgrading, log out and back in, and add the Fcitx5 input source again if necessary.

## Uninstallation

Switch to another input source first. If Rime is installed, uninstall the plugin before Fcitx5:

```sh
brew uninstall --cask mywnep/fcitx5/fcitx5-macos-rime
brew uninstall --cask mywnep/fcitx5/fcitx5-macos
```

After uninstalling Fcitx5, remove any remaining Fcitx5 input source from System Settings and log out. If you only uninstall Rime, restart Fcitx5.

Uninstallation preserves user configuration, custom schemas, dictionaries, and other plugins, including user data in `~/.config/fcitx5`, `~/.local/share/fcitx5`, and `~/Library/fcitx5`. Rime's plugin symlinks are removed automatically. Using `--zap` when uninstalling Fcitx5 additionally moves only `~/Library/fcitx5/cache` to the Trash.

## References

- [Fcitx5 macOS](https://github.com/fcitx/fcitx5-macos): upstream project.
- [Fcitx5 macOS documentation](https://fcitx-contrib.github.io/docs/): usage and configuration guides (Chinese).
- [fcitx5-plugins](https://github.com/fcitx-contrib/fcitx5-plugins): upstream plugin packages, including Rime.
- [Fcitx5 macOS Installer](https://github.com/fcitx-contrib/fcitx5-macos-installer): graphical installer maintained by fcitx-contrib and linked from the upstream README.
