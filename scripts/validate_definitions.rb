require "cask/cask_loader"
require "open3"
require "utils/topological_hash"

root = Pathname(__dir__).parent
load_cask = ->(token) { Cask::CaskLoader::FromContentLoader.new((root/"Casks/#{token}.rb").read).load(config: nil) }
main = load_cask.call("fcitx5-macos")
rime = load_cask.call("fcitx5-macos-rime")
input = main.artifacts.find { |a| a.is_a?(Cask::Artifact::InputMethod) }
raise "Unexpected target" unless input.target.to_s == "/Library/Input Methods/Fcitx5.app"
raise "Cask versions differ" unless main.version.to_s == rime.version.to_s
{ sequoia: "15", tahoe: "26" }.each do |os, icon|
  Homebrew::SimulateSystem.with(os: os) do
    simulated = load_cask.call("fcitx5-macos")
    artifacts = simulated.artifacts.to_a.sort
    preparation = artifacts.find { |a| a.is_a?(Cask::Artifact::PreflightSteps) }
    raise "Wrong icon for #{os}" unless preparation.steps.fetch(0).fetch("source").fetch("path").end_with?("menu_icon_#{icon}.pdf")
    raise "Icon copy must precede signing" unless artifacts.index(preparation) < artifacts.index { |a| a.is_a?(Cask::Artifact::Installer) }
  end
end
raise "Missing main cask dependency" unless rime.depends_on.cask == [main.token]

# Expose this checkout as an installed tap only inside this test process.
tap = Tap.fetch("test/fcitx5")
tap.define_singleton_method(:path) { root }
installed_taps = Tap.method(:installed)
begin
  Tap.define_singleton_method(:installed) { [tap] }
  graph = Utils::TopologicalHash.graph_package_dependencies(rime)
  dependency = graph.fetch(rime).fetch(0)
  raise "Wrong dependency resolved" unless dependency.sourcefile_path == root/"Casks/fcitx5-macos.rb"
  raise "Dependency order incorrect" unless graph.tsort.map(&:token) == [main.token, rime.token]
ensure
  Tap.define_singleton_method(:installed, installed_taps)
end
uninstall = rime.artifacts.find { |a| a.is_a?(Cask::Artifact::Uninstall) }
script = uninstall.directives.fetch(:script)
raise "Cleanup must succeed without sudo" unless script[:must_succeed] && script[:sudo] == false
raise "Cleanup script missing" unless script[:args] == ["#{rime.staged_path}/uninstall-rime"]
raise "Unsafe broad deletion" if uninstall.directives.key?(:delete) || uninstall.directives.key?(:trash)
installer = rime.artifacts.find { |a| a.is_a?(Cask::Artifact::Installer) }
raise "Unexpected installer" unless installer.path.to_s == "install-rime" && Array(installer.args[:args]).empty?
generated = rime.artifacts.grep(Cask::Artifact::GeneratedScript).map(&:to_args).to_h
raise "Expected separate scripts" unless generated.keys.sort == ["install-rime", "uninstall-rime"]
raise "Missing data checksum" unless generated.fetch("install-rime")[:content].match?(/^data_sha256="[a-f0-9]{64}"$/)
generated.each do |name, options|
  output, status = Open3.capture2e("/bin/zsh", "-n", stdin_data: options[:content])
  raise "Invalid #{name}: #{output}" unless status.success?
end
puts "PASS both casks, main dependency resolution and ordering, matched versions, input-method target and automatic cleanup directive"
