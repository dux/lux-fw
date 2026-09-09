require 'test_helper'
require 'open3'
require 'tmpdir'

describe 'lux new' do
  before do
    FileUtils.mkdir_p Lux.fw_root.join('tmp')
    @workspace = Dir.mktmpdir('lux-new-', Lux.fw_root.join('tmp'))
  end

  after do
    FileUtils.remove_entry @workspace
  end

  # Same compound command the generator runs; bound once so the expectations
  # below and the fail_on loop cannot drift apart.
  CREATE_DB ||= "psql --host=localhost --dbname=my_app_development --command='' 2>/dev/null || createdb --host=localhost my_app_development"

  def scaffold name = 'my-app', choice: "1\n", fail_on: nil, installed: false, chdir: @workspace
    framework = Lux.fw_root.to_s
    if installed
      gem_home = File.join(@workspace, 'gem-home')
      framework = File.join(gem_home, 'gems/lux-fw')
      FileUtils.mkdir_p File.join(framework, 'bin/cli')
      FileUtils.cp Lux.fw_root.join('bin/lux'), File.join(framework, 'bin/lux')
      FileUtils.cp Lux.fw_root.join('bin/cli/new_hammer.rb'), File.join(framework, 'bin/cli/new_hammer.rb')
      File.symlink Lux.fw_root.join('starter'), File.join(framework, 'starter')
    end
    runner = <<~'CODE'
      require 'lux-hammer'
      require 'json'
      if ENV['LUX_NEW_GEM_HOME']
        Gem.define_singleton_method(:path) { [ENV.fetch('LUX_NEW_GEM_HOME')] }
      end
      module Hammer::Shell
        def sh(command)
          if command == 'bundle install' && File.read('Gemfile').include?("path: '.gems/lux-fw'")
            raise 'local Lux is missing before bundle install' unless File.directory?('.gems/lux-fw')
          end
          puts "SETUP #{JSON.generate([Dir.pwd, command, ENV.values_at('BUNDLE_GEMFILE', 'LUX_ENV', 'DB_MAIN')])}"
          error "command failed: #{command}" if command == ENV['LUX_NEW_FAIL_ON']
          true
        end

        def exec(*command)
          puts "SERVER #{JSON.generate([Dir.pwd, command])}"
        end
      end
      load ARGV.shift
    CODE
    Open3.capture3({ 'LUX_NEW_FAIL_ON' => fail_on, 'LUX_NEW_GEM_HOME' => gem_home }, RbConfig.ruby, '-e', runner,
      File.join(framework, 'bin/lux'), 'new', *Array(name),
      chdir: chdir, stdin_data: choice)
  end

  def check_app choice, checks
    output, errors, status = scaffold(choice: "#{choice}\n")
    assert status.success?, output + errors
    setup = <<~'CODE'
      require 'test_helper'
      Lux.config.db = 'sqlite::memory:'
      Lux.debug = false
      Sequel::Model.require_valid_table = false
      require './config/app'
      require './db/auto_migrate'
      # LuxException/LuxExceptionLog only exist when the starter loads web_common
      models = [User]
      models += [LuxException, LuxExceptionLog] if defined?(LuxException)
      models.each do |klass|
        fields = Lux.schema(klass).db_schema
        Lux.db.create_table klass.table_name do
          String :ref, primary_key: true
          fields.each { |name, type, opts| column name, type, **opts }
        end
        klass.set_dataset(klass.table_name)
      end
      describe 'generated starter requests' do
        it 'serves its pages and enforces access' do
    CODE
    source = setup + checks + "\n  end\nend\n"
    output, errors, status = Open3.capture3(
      { 'LUX_SKIP_BUNDLER_REQUIRE' => '1', 'DB_MAIN' => nil }, RbConfig.ruby,
      '-I', Lux.fw_root.join('lib').to_s, '-I', Lux.fw_root.join('spec').to_s,
      '-e', source, chdir: File.join(@workspace, 'my-app'))
    assert status.success?, output + errors
  end

  it 'generates the basic starter and sets it up before starting the server' do
    output, errors, status = scaffold 'My App'
    assert status.success?, output + errors
    refute_includes output + errors, 'config.yaml not found'
    assert_includes output, 'hello-world'
    assert_includes output, 'full-minimal'
    path = File.join(@workspace, 'My App')
    steps = output.lines.filter_map { |line| JSON.parse(line.delete_prefix('SETUP ')) if line.start_with?('SETUP ') }
    assert_equal ['bundle install', CREATE_DB, 'bundle exec lux db:am'], steps.map { |step| step[1] }
    steps.each do |cwd, _, env|
      assert_equal path, cwd
      assert_equal [nil, 'development', nil], env
    end
    server = output.lines.find { |line| line.start_with?('SERVER ') }
    assert_equal [path, %w[bundle exec lux s]], JSON.parse(server.delete_prefix('SERVER '))
    assert_includes output, 'http://lvh.me:3000'
    refute_includes output, 'Next:'
    config = YAML.safe_load_file(File.join(path, 'config/config.yaml'))
    assert_equal 'My App', config.dig('default', 'app', 'name')
    assert_equal 'postgresql://localhost/my_app_development', config.dig('default', 'db', 'main')
    assert_match(/\A[0-9a-f]{128}\z/, config.dig('default', 'secret'))
    assert File.file?(File.join(path, '.gitignore'))
    assert File.file?(File.join(path, 'db/auto_migrate.rb'))
    # `lux s` runs the Procfile - without it a generated app installs and
    # migrates but never serves.
    assert_equal 'web: bundle exec lux server', File.read(File.join(path, 'Procfile')).strip
    assert_includes File.read(File.join(path, 'config/puma.rb')), 'lux_boot'
    # hello-world is the zero-build starter: no JS toolchain
    refute File.exist?(File.join(path, 'package.json'))
    # Object.const_missing never fires for a lookup inside a module, so
    # UserSession cannot autoload User - config/app.rb must load ./app itself
    assert_includes File.read(File.join(path, 'config/app.rb')), "Dir.require_all './app'"
    assert_includes File.read(File.join(path, 'config/config.yaml')), '- authcog'
    refute_includes File.read(File.join(path, 'config/config.yaml')), 'web_common'
    refute File.exist?(File.join(path, 'app/controllers/admin_controller.rb'))
    refute File.exist?(File.join(path, '.gitignore.template'))
    assert_includes File.read(File.join(path, '.gitignore')), '/config/config.yaml'
    assert_includes File.read(File.join(path, '.gitignore')), '/.gems/'
    assert File.symlink?(File.join(path, '.gems/lux-fw'))
    assert_equal Lux.fw_root.realpath.to_s, File.realpath(File.join(path, '.gems/lux-fw'))
    assert_includes File.read(File.join(path, 'Gemfile')), "gem 'lux-fw', path: '.gems/lux-fw'"

    _, _, status = scaffold 'another-app'
    assert status.success?
    other = YAML.safe_load_file(File.join(@workspace, 'another-app/config/config.yaml'))
    refute_equal config.dig('default', 'secret'), other.dig('default', 'secret')
  end

  it 'uses RubyGems when invoked from an installed framework gem' do
    output, errors, status = scaffold installed: true
    assert status.success?, output + errors
    path = File.join(@workspace, 'my-app')
    refute File.exist?(File.join(path, '.gems'))
    gemfile = File.read(File.join(path, 'Gemfile'))
    assert_includes gemfile, "gem 'lux-fw'\n"
    refute_includes gemfile, 'path:'
    refute_includes gemfile, '{{lux_source}}'
  end

  it 'cancels without creating the target or loading app config' do
    output, errors, status = scaffold choice: "q\n"
    assert status.success?, output + errors
    assert_empty Dir.children(@workspace)
    refute_includes output, 'Created'
    refute_includes output + errors, 'config.yaml not found'
  end

  it 'refuses an existing target and invalid names before prompting' do
    FileUtils.mkdir_p File.join(@workspace, 'my-app')
    output, errors, status = scaffold
    refute status.success?
    assert_includes errors, 'path already exists'
    refute_includes output, 'Choose a starter'
    assert_empty Dir.children(File.join(@workspace, 'my-app'))

    [[], ['one', 'two'], '---', 'a' * 47].each do |name|
      output, _, status = scaffold name
      refute status.success?
      refute_includes output, 'Choose a starter'
    end
  end

  it 'links declared local checkouts and installs JS deps for the full starter' do
    output, errors, status = scaffold choice: "2\n"
    assert status.success?, output + errors
    path = File.join(@workspace, 'my-app')

    steps = output.lines.filter_map { |line| JSON.parse(line.delete_prefix('SETUP ')) if line.start_with?('SETUP ') }
    assert_equal ['bundle install', 'bun install', CREATE_DB, 'bundle exec lux db:am'], steps.map { |step| step[1] }

    gemfile = File.read(File.join(path, 'Gemfile'))
    assert_includes gemfile, "lgem 'lux-fw'"
    assert_includes gemfile, "lgem 'lux-hammer'"
    # every lgem and every "file:.gems/x" dep gets a link when the checkout exists
    %w[lux-fw lux-hammer].each do |name|
      assert File.symlink?(File.join(path, ".gems/#{name}")), "missing .gems/#{name}"
    end
    package = File.read(File.join(path, 'package.json'))
    assert_includes package, '"fez": "file:.gems/fez"'
    assert_includes package, '"postwind": "file:.gems/postwind"'
    assert_equal 'my_app', JSON.parse(package)['name']

    procfile = File.read(File.join(path, 'Procfile'))
    assert_includes procfile, 'bun x rollup -cw'
    assert_includes procfile, 'web: bundle exec lux server'
    assert_includes File.read(File.join(path, '.gitignore')), '/node_modules/'
    assert_includes File.read(File.join(path, 'config/config.yaml')), '- web_common'
  end

  it 'refuses to generate inside a framework checkout' do
    # A fake marker rather than the real checkout, so a regressed guard cannot
    # write a generated app into the repo.
    checkout = File.join(@workspace, 'fake-fw')
    FileUtils.mkdir_p checkout
    FileUtils.touch File.join(checkout, 'lux-fw.gemspec')

    output, errors, status = scaffold chdir: checkout
    assert status.success?, output + errors
    assert_includes output, "Can't run in lux folder"
    refute_includes output, 'Choose a starter'
    assert_equal ['lux-fw.gemspec'], Dir.children(checkout)
  end

  it 'stops at a failed setup step and keeps the generated app' do
    ['bundle install', CREATE_DB, 'bundle exec lux db:am'].each_with_index do |command, index|
      output, errors, status = scaffold fail_on: command
      refute status.success?
      assert_includes errors, "command failed: #{command}"
      assert_equal index + 1, output.lines.count { |line| line.start_with?('SETUP ') }
      refute_includes output, 'SERVER '
      assert File.file?(File.join(@workspace, 'my-app/config/config.yaml'))
      FileUtils.remove_entry File.join(@workspace, 'my-app')
    end
  end

  it 'packages both starters, their config templates and framework assets' do
    spec = Gem::Specification.load(Lux.fw_root.join('lux-fw.gemspec').to_s)
    %w[hello-world full-minimal].each do |name|
      assert_includes spec.files, "starter/#{name}/config/config.yaml"
      assert_includes spec.files, "starter/#{name}/.gitignore.template"
      assert_includes spec.files, "starter/#{name}/Procfile"
      assert_includes spec.files, "starter/#{name}/config/puma.rb"
    end
    assert_includes spec.files, 'starter/hello-world/public/components/app-nav.fez'
    assert_includes spec.files, 'starter/full-minimal/package.json'
    # the extracted plugin has to ship too, or authcog apps break on install
    assert_includes spec.files, 'plugins/authcog/load/authcog_controller.rb'
    assert_includes spec.files, 'plugins/authcog/load/user_session.rb'
    assert_includes spec.files, 'plugins/web_common/config.yaml'
    assert_includes spec.files, 'assets/controller/error_page.html.erb'
    refute spec.files.any? { |file| File.basename(file).include?('.tmp.') }
    refute spec.files.any? { |file| file.start_with?('assets/new_app/') }
  end

  it 'renders the basic starter and completes AuthCog sign-in and signed logout' do
    check_app 1, <<~'CODE'
      response = Lux.render.get('/')
      assert_equal 200, (response).status
      assert_includes response.body, 'Welcome to My App'
      assert_includes response.body, 'postwind@'
      assert_includes response.body, '@dinoreic/fez@'
      assert_includes response.body, '<app-nav>'
      assert_includes response.body, 'id="lux-state"'
      # fez binds Pjax only when the layout ships a container carrying an id
      assert_includes response.body, 'id="page"'
      assert_includes response.body, 'pjax'
      assert_equal 200, (Lux.render.get('/components/app-nav.fez')).status
      assert_equal 404, (Lux.render.get('/missing')).status

      about = Lux.render.get('/about')
      assert_equal 200, (about).status
      assert_includes about.body, 'simple Lux demo starter app'
      assert_equal 400, (Lux.render.get('/authcog')).status

      # no web_common: its constants and mounted admin area must be absent
      refute defined?(LuxException), 'web_common should not load in hello-world'
      assert defined?(UserSession), 'authcog plugin should load standalone'

      login = Lux.render.get('http://lvh.me:3000/login')
      assert_equal 'https://auth.authcog.com/domain:lvh.me/port:3000', login.headers['location']
      AuthcogController.class_eval do
        def fetch_identity(_hash)
          { email: 'new@example.com', name: '<b>New user</b>', provider: 'test' }
        end
      end
      callback = Lux.render.get('/authcog', params: { callback: 'a' * 40 })
      assert_equal 302, (callback).status
      member = User.first(email: 'new@example.com')
      refute_nil member
      assert_equal member.ref, callback.session[:user_ref]
      page = Lux.render.get('/', session: { user_ref: member.ref })
      assert_includes page.body, 'Hello'
      assert_includes page.body, '&lt;b&gt;New user&lt;/b&gt;'
      # the nav is a fez component, so the sign-out link ships in the exported
      # state rather than the server-rendered markup
      link = page.body[/"logout_url"\s*:\s*"([^"]+)"/, 1]
      refute_nil link, 'logout_url missing from window.app.current.user'
      logout = Lux.render.get(link, session: { user_ref: member.ref })
      assert_equal 302, (logout).status
      assert_nil logout.session[:user_ref]
    CODE
  end

  it 'protects the workspace and admin area and preserves the login destination' do
    check_app 2, <<~'CODE'
      promo = Lux.render.get('/')
      assert_equal 200, (promo).status
      assert_includes promo.body, 'Make room for your next idea.'
      assert_includes promo.body, 'href="/app"'
      assert_includes promo.body, 'href="/about"'
      refute_includes promo.body, 'href="/admin"'
      # fez binds Pjax only when the layout ships a container carrying an id
      assert_includes promo.body, 'id="page"'
      assert_includes promo.body, 'pjax'

      # promo is convention routed, so /about is a template with no action
      about = Lux.render.get('/about')
      assert_equal 200, (about).status
      assert_includes about.body, 'simple Lux demo starter app'
      assert_equal 404, (Lux.render.get('/missing')).status

      %w[/app /admin].each do |path|
        guest = Lux.render.get(path)
        assert_equal 302, (guest).status
        assert_equal '/login', URI.parse(guest.headers['location']).path
        assert_equal path, guest.session[:redirect_after_login]
      end
      AuthcogController.class_eval do
        def fetch_identity(_hash)
          { email: 'member@example.com', name: 'Member', provider: 'test' }
        end
      end
      callback = Lux.render.get('/authcog', params: { callback: 'a' * 40 },
        session: { redirect_after_login: '/app' })
      assert_equal '/app', URI.parse(callback.headers['location']).path
      member = User.first(email: 'member@example.com')
      auth = { user_ref: member.ref }
      assert_equal 200, (Lux.render.get('/app', session: auth)).status
      assert_equal 403, (Lux.render.get('/admin', session: auth)).status
      assert_equal 404, (Lux.render.get('/app/missing', session: auth)).status
      assert_equal 404, (Lux.render.get('/admin/missing', session: auth)).status
      member.update(is_admin: true)
      admin = Lux.render.get('/admin', session: auth)
      assert_equal 200, (admin).status
      assert_includes admin.body, 'Registered users'
      assert_includes admin.body, 'href="/admin"'
      member.update(is_locked: true)
      assert_equal 302, (Lux.render.get('/admin', session: auth)).status
      member.update(is_locked: false, is_deleted: true)
      assert_equal 302, (Lux.render.get('/app', session: auth)).status
    CODE
  end
end
