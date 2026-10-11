# Fcitx5 macOS Homebrew tap

[English](README.md) | 简体中文

提供 [Fcitx5 macOS](Casks/fcitx5-macos.rb) 稳定版和可选的 [Rime 插件](Casks/fcitx5-macos-rime.rb)。支持 Apple Silicon 和 Intel，要求 macOS 13.3+ 及新版 Homebrew。

## 安装

添加 tap 并安装本体：

```sh
brew tap mywnep/fcitx5
brew trust --cask mywnep/fcitx5/fcitx5-macos
brew install --cask mywnep/fcitx5/fcitx5-macos
```

Fcitx5 安装到 `/Library/Input Methods/Fcitx5.app`，安装时可能需要管理员密码。

需要 Rime 时安装：

```sh
brew trust --cask mywnep/fcitx5/fcitx5-macos-rime
brew install --cask mywnep/fcitx5/fcitx5-macos-rime
```

Rime 会自动安装缺失的 Fcitx5 本体，但不附带输入方案。已有手动安装的本体或插件时，先备份用户数据并使用原安装方式移除对应程序，再通过 Homebrew 安装。

## 使用

安装本体后注销并重新登录，在「系统设置 → 键盘 → 输入法」中添加 Fcitx5。

安装 Rime 后重启 Fcitx5，在其输入法配置中添加 Rime。自行安装[万象](https://github.com/amzxyz/rime-wanxiang/releases)等完整方案及所需数据，并按方案说明部署。Rime 用户数据目录默认为 `~/.local/share/fcitx5/rime`；若修改过环境配置，可从 Rime 配置界面打开实际目录。

通过 Homebrew 更新本体和插件，保持版本配套。升级前先切换到其他输入法，按以下顺序执行；未安装 Rime 时跳过最后一行：

```sh
brew update
brew upgrade --cask --greedy mywnep/fcitx5/fcitx5-macos
brew upgrade --cask mywnep/fcitx5/fcitx5-macos-rime
```

升级后注销并重新登录，必要时重新添加 Fcitx5 输入源。

## 卸载

先切换到其他输入法。若安装了 Rime，先卸载插件，再卸载本体：

```sh
brew uninstall --cask mywnep/fcitx5/fcitx5-macos-rime
brew uninstall --cask mywnep/fcitx5/fcitx5-macos
```

卸载本体后，在系统设置中移除残留的 Fcitx5 输入源，并注销登录。仅卸载 Rime 时，重启 Fcitx5 即可。

卸载会保留用户配置、自定义方案、词库和其他插件，包括 `~/.config/fcitx5`、`~/.local/share/fcitx5` 和 `~/Library/fcitx5` 中的用户数据。Rime 的程序链接会自动清理。本体卸载时加 `--zap`，仅额外将 `~/Library/fcitx5/cache` 移入废纸篓。

## 参考资源

- [Fcitx5 macOS](https://github.com/fcitx/fcitx5-macos)：上游项目。
- [Fcitx5 macOS 文档](https://fcitx-contrib.github.io/docs/)：使用与配置指南。
- [fcitx5-plugins](https://github.com/fcitx-contrib/fcitx5-plugins)：包含 Rime 在内的上游插件包。
- [Fcitx5 macOS Installer](https://github.com/fcitx-contrib/fcitx5-macos-installer)：fcitx-contrib 维护的图形安装器，上游 README 中提供了入口。
