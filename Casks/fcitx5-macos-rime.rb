cask "fcitx5-macos-rime" do
  arch arm: "arm64", intel: "x86_64"

  version "0.4.0"
  sha256 arm:   "54c3d0aa39890d2fdb4695838053784fc89521bf2c645dd5d3226bcafdf94d82",
         intel: "eec4675284d4e8ef4f341fc3346db2158c5df56789391a1d1f4e529bfee0758c"

  url "https://github.com/fcitx-contrib/fcitx5-plugins/releases/download/macos-#{version}/rime-#{arch}.tar.bz2"
  name "Fcitx5 macOS Rime"
  desc "Rime plugin for Fcitx5 macOS with user-installed schemas"
  homepage "https://github.com/fcitx-contrib/fcitx5-plugins"

  livecheck do
    skip "Updated together with the fcitx5-macos stable release"
  end

  depends_on cask: "fcitx5-macos"
  depends_on macos: :ventura

  generated_script "uninstall-rime", content: <<~SH
    #!/bin/zsh
    set -eu
    package_root=#{caskroom_path.to_s.shellescape}
    destination=#{"#{Dir.home}/Library/fcitx5".shellescape}
    for file in "$destination"/**/*(@DN); do
      target=$(/usr/bin/readlink "$file")
      if [[ $target == "$package_root/"* ]]; then
        /bin/rm -- "$file"
      fi
    done
  SH

  generated_script "install-rime", content: <<~SH
    #!/bin/zsh
    set -eu
    stage=#{staged_path.to_s.shellescape}
    package_root=#{caskroom_path.to_s.shellescape}
    destination=#{"#{Dir.home}/Library/fcitx5".shellescape}
    expected_version=#{version.to_s.shellescape}
    data_sha256="f7bed088fd8fc0d1a918f95b063c28f01c533ce50c745b4e29827d511f409b45"
    data_url="https://github.com/fcitx-contrib/fcitx5-plugins/releases/download/macos-#{version}/rime-any.tar.bz2"
    app="/Library/Input Methods/Fcitx5.app"
    payload="$stage/payload"
    fail() { print -u2 -- "$*"; exit 1; }

    plist="$app/Contents/Info.plist"
    actual_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
    actual_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
    [[ $actual_version == $expected_version && $actual_build == 0 ]] || fail "Expected stable Fcitx5 $expected_version (build 0); found $actual_version (build $actual_build). Upgrade both casks together."

    archive="$stage/rime-data.tar.bz2"
    if [[ ! -f $archive ]]; then
      /usr/bin/curl --fail --location --retry 3 --connect-timeout 30 --max-time 300 \\
        --proto '=https' --proto-redir '=https' --output "$archive.part" "$data_url"
      /bin/mv "$archive.part" "$archive"
    fi
    actual_sha256=$(/usr/bin/shasum -a 256 "$archive")
    [[ ${actual_sha256%% *} == $data_sha256 ]] || fail 'Rime data checksum mismatch; installation aborted.'

    temporary=$(/usr/bin/mktemp -d "$stage/payload.XXXXXXXX")
    trap '/bin/rm -rf -- "$temporary"' EXIT
    /usr/bin/tar -xjf "$archive" -C "$temporary" \\
      share/fcitx5 share/icons share/locale share/rime-data/fcitx5.yaml
    /bin/cp -R "$stage/lib" "$temporary/lib"
    print -rl -- "config_version: '0.0'" 'schema_list: []' > "$temporary/share/rime-data/default.yaml"
    /usr/bin/xattr -dr com.apple.quarantine "$temporary"

    files=()
    for file in "$temporary"/**/*(.DN) "$temporary"/**/*(@DN); do
      [[ -f $file ]] || fail "Invalid plugin file or dangling upstream link: $file"
      relative=${file#"$temporary/"}
      files+=("$relative")
      target="$destination/$relative"
      if [[ -e $target || -L $target ]]; then
        [[ -L $target && $(/usr/bin/readlink "$target") == "$package_root/"* ]] || fail "Existing plugin file: $target. Remove the old Rime plugin through its original manager first."
      fi
      parent=${target:h}
      while [[ $parent != $destination ]]; do
        [[ ! -L $parent ]] || fail "Refusing to write through directory symlink: $parent"
        [[ ! -e $parent || -d $parent ]] || fail "Not a directory: $parent"
        parent=${parent:h}
      done
    done

    /bin/rm -rf -- "$payload"
    /bin/mv "$temporary" "$payload"
    /bin/zsh "$stage/uninstall-rime"
    for relative in "${files[@]}"; do
      target="$destination/$relative"
      /bin/mkdir -p "${target:h}"
      /bin/ln -s "$payload/$relative" "$target"
    done
  SH

  installer script: {
    executable: "install-rime",
    sudo:       false,
  }

  uninstall script: {
    executable:   "/bin/zsh",
    args:         ["#{staged_path}/uninstall-rime"],
    sudo:         false,
    must_succeed: true,
  }

  caveats <<~EOS
    No schemas are bundled. Install your own schema in the Rime user data directory and deploy it. Add Rime in Fcitx5's input-method configuration. Restart Fcitx5 after installing, upgrading or uninstalling this plugin.

    Upgrade fcitx5-macos first, then this cask, keeping their versions matched.

    Uninstallation automatically removes this cask's plugin links and preserves user configuration, custom schemes, dictionaries and other plugins.
  EOS
end
