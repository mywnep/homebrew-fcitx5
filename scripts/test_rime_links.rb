require "cask/cask_loader"
require "tmpdir"
require "fileutils"
require "open3"
require "digest"
require "shellwords"
require "yaml"

abort "Usage: brew ruby scripts/test_rime_links.rb Fcitx5.app rime-ARCH.tar.bz2 rime-any.tar.bz2" unless ARGV.length == 3
app, native_archive, data_archive = ARGV.map { |arg| Pathname(arg).expand_path }
root = Pathname(__dir__).parent
cask = Cask::CaskLoader::FromContentLoader.new((root/"Casks/fcitx5-macos-rime.rb").read).load(config: nil)
generated = cask.artifacts.grep(Cask::Artifact::GeneratedScript).map(&:to_args)
install_template = cask.artifacts.find { |a| a.is_a?(Cask::Artifact::Installer) }
uninstall_template = cask.artifacts.find { |a| a.is_a?(Cask::Artifact::Uninstall) }

def run!(*args)
  output, status = Open3.capture2e(*args)
  raise output unless status.success?
  output
end

def snapshot(path)
  Dir.glob("#{path}/**/*", File::FNM_DOTMATCH).sort.filter_map do |file|
    if File.symlink?(file)
      [file.delete_prefix("#{path}/"), :link, File.readlink(file)]
    elsif File.file?(file)
      [file.delete_prefix("#{path}/"), :file, Digest::SHA256.file(file).hexdigest]
    end
  end
end

Dir.mktmpdir("fcitx5 rime cask tests ") do |directory|
  scratch = Pathname(directory)/"user's files $data"
  package_root = scratch/"Caskroom/fcitx5-macos-rime"
  stage = package_root/cask.version.to_s
  destination = scratch/"user/Library/fcitx5"
  prepare = lambda do |current_stage|
    current_stage.mkpath
    run!("/usr/bin/tar", "-xjf", native_archive.to_s, "-C", current_stage.to_s)
    FileUtils.cp(data_archive, current_stage/"rime-data.tar.bz2")
    paths = { "stage" => current_stage, "package_root" => package_root,
              "destination" => destination, "app" => app }
    generated.each do |name, options|
      content = options[:content].gsub(/^(stage|package_root|destination|app)=.*$/) do
        "#{Regexp.last_match(1)}=#{paths.fetch(Regexp.last_match(1)).to_s.shellescape}"
      end
      (current_stage/name).write(content)
      (current_stage/name).chmod(0755)
      run!("/bin/zsh", "-n", (current_stage/name).to_s)
    end
  end
  map_arguments = lambda do |arguments, current_stage|
    arguments.map do |arg|
      arg.to_s.gsub(cask.staged_path.to_s, current_stage.to_s)
         .gsub(cask.caskroom_path.to_s, package_root.to_s)
         .gsub("#{Dir.home}/Library/fcitx5", destination.to_s)
         .gsub("/Library/Input Methods/Fcitx5.app", app.to_s)
    end
  end
  install = lambda do |current_stage|
    artifact = Cask::Artifact::Installer.from_args(cask, script: {
      executable: (current_stage/install_template.path).to_s, sudo: false,
    })
    artifact.install_phase(command: SystemCommand)
  end
  uninstall = lambda do |current_stage, upgrade = false|
    directive = uninstall_template.directives.fetch(:script).dup
    directive[:args] = map_arguments.call(directive[:args], current_stage)
    artifact = Cask::Artifact::Uninstall.from_args(cask, script: directive)
    artifact.uninstall_phase(command: SystemCommand, upgrade: upgrade)
  end
  expect_install_failure = lambda do |current_stage, message|
    before = snapshot(destination)
    output, status = Open3.capture2e("/bin/zsh", (current_stage/"install-rime").to_s)
    raise "Expected #{message}: #{output}" if status.success? || !output.include?(message)
    raise "Failed install changed destination" unless before == snapshot(destination)
  end

  prepare.call(stage)
  user_rime = scratch/"user/.local/share/fcitx5/rime"
  user_rime.mkpath
  (user_rime/"default.yaml").write("schema_list:\n  - schema: wanxiang\n")
  (user_rime/"wanxiang.schema.yaml").write("schema:\n  schema_id: wanxiang\n")
  user_rime_before = snapshot(user_rime)
  run!("/usr/bin/xattr", "-w", "com.apple.quarantine", "0081;0;Homebrew;", (stage/"lib/fcitx5/librime.so").to_s)
  install.call(stage)
  payload = stage/"payload"
  attributes = run!("/usr/bin/xattr", (payload/"lib/fcitx5/librime.so").to_s)
  raise "Plugin quarantine was preserved" if attributes.include?("com.apple.quarantine")
  expected = run!("/usr/bin/tar", "-tjf", data_archive.to_s).lines.map(&:chomp).select do |file|
    !file.end_with?("/") && (file.start_with?("share/fcitx5/", "share/icons/", "share/locale/") || file == "share/rime-data/fcitx5.yaml")
  end + ["lib/fcitx5/librime.so", "share/rime-data/default.yaml"]
  raise "Unexpected payload files" unless snapshot(payload).map(&:first).sort == expected.sort
  defaults = YAML.safe_load((payload/"share/rime-data/default.yaml").read)
  raise "Bundled schemas remain" unless defaults.fetch("schema_list").empty?
  raise "User schema changed during installation" unless snapshot(user_rime) == user_rime_before
  expected.each do |relative|
    link = destination/relative
    raise "Missing or broken entry: #{relative}" unless link.symlink? && link.file?
    raise "Wrong link target: #{relative}" unless link.readlink == payload/relative
    raise "Different contents: #{relative}" unless Digest::SHA256.file(link).hexdigest == Digest::SHA256.file(payload/relative).hexdigest
  end
  before = snapshot(destination)
  legacy_descriptor = destination/"plugin/rime.json"
  legacy_descriptor.parent.mkpath
  File.symlink(stage/"plugin/rime.json", legacy_descriptor)
  install.call(stage)
  raise "Old cask descriptor link remains" if legacy_descriptor.symlink? || legacy_descriptor.exist?
  raise "Reinstall changed links" unless snapshot(destination) == before
  raise "User schema changed during reinstall" unless snapshot(user_rime) == user_rime_before
  puts "PASS all #{expected.length} entries including upstream aliases; idempotent installer; paths with spaces, quotes and dollars"
  puts "PASS no bundled schemas, dictionaries, OpenCC data or Plugin Manager descriptor; old descriptor link removed; user schema preserved"

  loader = scratch/"load-rime"
  run!("/usr/bin/clang", (root/"tests/rime_load.c").to_s, "-Wl,-export_dynamic", "-Wl,-rpath,#{app}/Contents/lib", "-o", loader.to_s)
  real = run!(loader.to_s, (payload/"lib/fcitx5/librime.so").to_s)
  linked = run!(loader.to_s, (destination/"lib/fcitx5/librime.so").to_s)
  raise "Linked load differs" unless real == linked
  puts linked.strip

  conflict = destination/"share/rime-data/default.yaml"
  conflict.unlink
  conflict.write("user custom file\n")
  expect_install_failure.call(stage, "Existing plugin file:")
  conflict.unlink
  foreign = scratch/"other-manager.txt"
  foreign.write("external data")
  File.symlink(foreign, conflict)
  expect_install_failure.call(stage, "Existing plugin file:")
  conflict.unlink
  File.symlink(payload/"share/rime-data/default.yaml", conflict)

  icons = destination/"share/icons"
  external_icons = scratch/"external-icons"
  FileUtils.mv(icons, external_icons)
  File.symlink(external_icons, icons)
  expect_install_failure.call(stage, "directory symlink")
  icons.unlink
  FileUtils.mv(external_icons, icons)
  puts "PASS ordinary-file, foreign-link and directory-link conflict protection"

  (stage/"rime-data.tar.bz2").write("bad archive")
  expect_install_failure.call(stage, "checksum mismatch")
  FileUtils.cp(data_archive, stage/"rime-data.tar.bz2")
  script = stage/"install-rime"
  original_script = script.read
  test_app = scratch/"version-check/Fcitx5.app"
  test_plist = test_app/"Contents/Info.plist"
  test_plist.parent.mkpath
  FileUtils.cp(app/"Contents/Info.plist", test_plist)
  begin
    script.write(original_script.sub(/^app=.*$/) { "app=#{test_app.to_s.shellescape}" })
    run!("/usr/libexec/PlistBuddy", "-c", "Set :CFBundleShortVersionString 999.0.0", test_plist.to_s)
    expect_install_failure.call(stage, "Expected stable Fcitx5")
    run!("/usr/libexec/PlistBuddy", "-c", "Set :CFBundleShortVersionString #{cask.version}", test_plist.to_s)
    run!("/usr/libexec/PlistBuddy", "-c", "Set :CFBundleVersion 6", test_plist.to_s)
    expect_install_failure.call(stage, "Expected stable Fcitx5")
  ensure
    script.write(original_script)
  end
  puts "PASS data checksum, version mismatch and non-stable build rejection"

  user_file = destination/"share/rime-data/my.custom.yaml"
  user_file.write("custom: preserved\n")
  foreign_link = destination/"unrelated-link"
  File.symlink(foreign, foreign_link)
  dictionary = scratch/"user/.local/share/fcitx5/rime/user.userdb"
  dictionary.parent.mkpath
  dictionary.write("user dictionary sentinel")
  user_rime_before = snapshot(user_rime)
  config = scratch/"user/.config/fcitx5/profile"
  config.parent.mkpath
  config.write("user profile sentinel")
  assert_user_data = lambda do
    raise "User schema changed" unless snapshot(user_rime) == user_rime_before
    raise "User file removed" unless user_file.read == "custom: preserved\n"
    raise "Foreign link removed" unless foreign_link.symlink? && foreign.read == "external data"
    raise "Dictionary changed" unless dictionary.read == "user dictionary sentinel"
    raise "Profile changed" unless config.read == "user profile sentinel"
  end
  owned_links = -> { snapshot(destination).select { |e| e[1] == :link && e[2].start_with?("#{package_root}/") } }

  package_before = snapshot(stage)
  uninstall.call(stage, true)
  raise "Upgrade failed to unlink" unless owned_links.call.empty?
  raise "Uninstall modified staged payload" unless snapshot(stage) == package_before
  assert_user_data.call
  next_stage = package_root/"next-version"
  prepare.call(next_stage)
  install.call(next_stage)
  FileUtils.remove_entry(stage)
  expected.each { |file| raise "Upgrade link points to old stage" unless (destination/file).file? && (destination/file).readlink.to_s.start_with?(next_stage.to_s) }
  puts "PASS real Homebrew upgrade uninstall hook, relinking and old-stage removal"

  uninstall.call(next_stage)
  uninstall.call(next_stage)
  raise "Normal uninstall left links" unless owned_links.call.empty?
  assert_user_data.call
  puts "PASS real Homebrew uninstall hook and repeated cleanup preserve user data"

  install.call(next_stage)
  FileUtils.remove_entry(next_stage/"payload")
  uninstall.call(next_stage)
  raise "Dangling links remain" unless owned_links.call.empty?
  assert_user_data.call
  puts "PASS automatic dangling-link cleanup when payload is already missing"
end
