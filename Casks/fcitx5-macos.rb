cask "fcitx5-macos" do
  arch arm: "arm64", intel: "x86_64"

  version "0.4.1"
  sha256 arm:   "0696b46ea02e5bcc403f2bdfad2017b68210250b918ed3e02a8a4bf66d57ff97",
         intel: "747424323831da6f09247ebb55037951a0513b79f2ce0438befdab2ee5b95759"

  url "https://github.com/fcitx/fcitx5-macos/releases/download/#{version}/Fcitx5-#{arch}.tar.bz2"
  name "Fcitx5 macOS"
  desc "Input method framework for macOS"
  homepage "https://github.com/fcitx/fcitx5-macos"

  livecheck do
    url :url
    strategy :github_latest
  end

  auto_updates true
  depends_on macos: :ventura # The exact 13.3 minimum is checked below.

  on_sequoia :or_older do
    preflight_steps do
      copy "Fcitx5.app/Contents/Resources/menu_icon_15.pdf", "Fcitx5.app/Contents/Resources/menu_icon.pdf"
    end
  end

  on_tahoe :or_newer do
    preflight_steps do
      copy "Fcitx5.app/Contents/Resources/menu_icon_26.pdf", "Fcitx5.app/Contents/Resources/menu_icon.pdf"
    end
  end

  generated_script "prepare-fcitx5", content: <<~'SH'
    #!/bin/zsh
    set -eu
    app="$1"
    os_version=$(/usr/bin/sw_vers -productVersion)
    autoload -Uz is-at-least
    if ! is-at-least 13.3 "$os_version"; then
      print -u2 'Fcitx5 requires macOS 13.3 or later.'
      exit 1
    fi
    /usr/bin/xattr -dr com.apple.quarantine "$app"
    /usr/bin/codesign --force --sign - --deep "$app"
    /usr/bin/codesign --verify --deep --strict "$app"
  SH

  installer script: {
    executable: "prepare-fcitx5",
    args:       ["#{staged_path}/Fcitx5.app"],
    sudo:       false,
  }

  input_method "Fcitx5.app", target: "/Library/Input Methods/Fcitx5.app"

  zap trash: "~/Library/fcitx5/cache"

  caveats <<~EOS
    Switch to another input source before upgrading or uninstalling. After installation or upgrade, log out and back in, then add Fcitx5 in System Settings > Keyboard > Input Sources if necessary. After uninstalling, remove any remaining Fcitx5 entry from Input Sources and log out.

    To upgrade: brew upgrade --cask --greedy fcitx5-macos

    Uninstallation preserves configuration, custom schemes, dictionaries and plugins in ~/.config/fcitx5, ~/.local/share/fcitx5 and ~/Library/fcitx5. With --zap, only ~/Library/fcitx5/cache is additionally removed.
  EOS
end
