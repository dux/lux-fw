require 'test_helper'
require 'tmpdir'
require 'fileutils'

# Lux::Root is the ordered overlay that replaces plugin mount symlinks. These
# specs build throwaway mount roots under tmp and register them as overlays,
# cleaning the overlay list afterwards so other lux_tests are unaffected.
describe 'Lux::Root' do
  before do
    @base = File.join(Dir.tmpdir, "lux_root_spec_#{Process.pid}_#{rand(1_000_000)}")
    @mount = File.join(@base, 'plugin_a')
    FileUtils.mkdir_p File.join(@mount, 'app/views/main')
    FileUtils.mkdir_p File.join(@mount, 'app/models')
    FileUtils.mkdir_p File.join(@mount, 'lib')
    File.write File.join(@mount, 'app/views/main/root.haml'), 'plugin'
    File.write File.join(@mount, 'app/models/root_spec_thing.rb'), 'class RootSpecThing; end'
    File.write File.join(@mount, 'lib/root_spec_tool.rb'), 'ROOT_SPEC_TOOL = 1'

    Lux::Root.add @mount
  end

  after do
    Lux::Root.overlays.reject! { |path| path.to_s.start_with?(@base) }
    FileUtils.rm_rf @base
    Object.send(:remove_const, :RootSpecThing) if Object.const_defined?(:RootSpecThing, false)
  end

  it 'keeps the app root first and plugin mounts after it' do
    roots = Lux::Root.roots.map(&:to_s)
    assert_equal Lux.root.to_s, roots.first
    assert_includes roots, @mount
  end

  it 'resolves a path across roots' do
    found = Lux.root.path('app/views/main/root.haml').to_s
    assert_equal File.join(@mount, 'app/views/main/root.haml'), found
  end

  it 'returns nil from resolve when nothing matches' do
    assert_nil Lux.root.resolve('app/views/nope.haml')
  end

  it 'raises NotFound naming every location tried' do
    error = assert_raises(Lux::Root::NotFound) { Lux.root.path('app/views/nope.haml') }
    assert_includes error.message, 'app/views/nope.haml'
    assert_includes error.message, @mount
    assert_includes error.message, Lux.root.to_s
  end

  it 'merges files across roots' do
    found = Lux.root.files('app/views/**/*.haml').map(&:to_s)
    assert_includes found, File.join(@mount, 'app/views/main/root.haml')
  end

  it 'first root shadows later roots by relative path' do
    shadow = File.join(@base, 'plugin_b')
    FileUtils.mkdir_p File.join(shadow, 'app/views/main')
    File.write File.join(shadow, 'app/views/main/root.haml'), 'shadow'
    Lux::Root.add shadow

    assert_equal File.join(@mount, 'app/views/main/root.haml'),
                 Lux.root.path('app/views/main/root.haml').to_s
  end

  it 'requires a lib by name' do
    refute defined?(ROOT_SPEC_TOOL)
    Lux.root.lib('lib/root_spec_tool')
    assert_equal 1, ROOT_SPEC_TOOL
  end

  it 'autoloads a top-level constant by underscored basename' do
    refute Object.const_defined?(:RootSpecThing, false)
    assert Lux.root.autoload_const(:RootSpecThing)
    assert Object.const_defined?(:RootSpecThing, false)
  end

  it 'mirrors a plugin path under the writable app root' do
    mirrored = Lux.root.mirror(File.join(@mount, 'app/views/main/root.haml')).to_s
    assert_equal Lux.root.join('app/views/main/root.haml').to_s, mirrored
  end

  it 'prettifies a path relative to whichever root owns it' do
    assert_equal './app/views/main/root.haml',
                 Lux.root.pretty(File.join(@mount, 'app/views/main/root.haml'))
  end

  it 'keeps Pathname behaviour intact' do
    assert_kind_of Lux::Root, Lux.root
    assert_kind_of Pathname, Lux.root.join('app')
    assert_equal Lux.root.to_s, Pathname.new(Lux.root).to_s
    assert_equal 'app', Lux.root.join('app').relative_path_from(Lux.root).to_s
  end
end
