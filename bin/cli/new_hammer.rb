require 'fileutils'
require 'securerandom'
require 'bundler'

task :new do
  desc 'Create, set up and start a new Lux application'
  example 'new my-app'

  proc do |opts|
    name = opts[:args].first
    error 'usage: lux new APP_NAME' unless name && opts[:args].length == 1

    target = File.expand_path(name)
    error "path already exists: #{name}" if File.exist?(target) || File.symlink?(target)

    app_under = File.basename(target).gsub(/[^a-zA-Z0-9]+/, '_').downcase.gsub(/\A_+|_+\z/, '')
    error 'app name must contain a letter or number' if app_under.empty?
    app_under = "app_#{app_under}" if app_under.match?(/\A\d/)
    error 'app name is too long for a PostgreSQL database name (maximum 46 characters)' if app_under.length > 46
    app_name  = app_under.split('_').map(&:capitalize).join(' ')
    db_name   = "#{app_under}_development"
    secret    = SecureRandom.hex(64)
    framework = File.realpath('../..', __dir__)
    local_fw  = !Gem.path.any? { |path| framework.start_with?("#{File.expand_path(path)}/gems/") }
    vars      = {
      'app' => app_under, 'App' => app_name, 'secret' => secret,
      'lux_source' => local_fw ? ", path: '.gems/lux-fw'" : ''
    }

    starters = File.join(framework, 'starter')
    folders = Dir.children(starters).select do |folder|
      !folder.start_with?('.') && !folder.include?('.tmp.') && File.directory?(File.join(starters, folder))
    end.sort_by { |folder| [folder == 'hello-world' ? 0 : 1, folder] }
    error 'no starter folders found' if folders.empty?

    selected = choose 'Choose a starter', folders
    next unless selected
    skeleton = File.join(starters, folders[selected])

    Dir.glob("#{skeleton}/**/*", File::FNM_DOTMATCH).sort.each do |src|
      base = File.basename(src)
      next if File.directory?(src) || base == '.' || base == '..' || base.include?('.tmp.')

      rel  = src.sub("#{skeleton}/", '').delete_suffix('.template')
      dst  = File.join(target, rel)
      data = File.read(src).gsub(/\{\{(\w+)\}\}/) { vars[$1] || $~[0] }

      FileUtils.mkdir_p(File.dirname(dst))
      File.write(dst, data)
      say.green '  create  %s' % "#{name}/#{rel}"
    end

    # Which local checkouts the starter wants linked, read from what it declares:
    # `lgem 'x'` in the Gemfile and `"file:.gems/x"` in package.json.
    package_json = File.join(target, 'package.json')
    wanted = ['lux-fw']
    wanted += File.read(File.join(target, 'Gemfile')).scan(/^\s*lgem '([^']+)'/).flatten
    wanted += File.read(package_json).scan(%r{"file:\.gems/([^"]+)"}).flatten if File.exist?(package_json)

    if local_fw
      FileUtils.mkdir_p File.join(target, '.gems')
      wanted.uniq.each do |gem_name|
        source = File.expand_path("../#{gem_name}", framework)
        next unless File.directory?(source)

        File.symlink source, File.join(target, ".gems/#{gem_name}")
        say.green '  link    %s/.gems/%s -> %s' % [name, gem_name, source]
      end
    end

    puts
    say.yellow 'Setting up %s...' % name
    Dir.chdir(target) do
      Bundler.with_unbundled_env do
        ENV['LUX_ENV'] = 'development'

        sh 'bundle install'
        sh 'bun install' if File.exist?('package.json')
        # Connect first so a re-run over an existing database is not an error.
        # When the server is down both fail and createdb reports the real cause.
        sh "psql --host=localhost --dbname=#{db_name} --command='' 2>/dev/null || createdb --host=localhost #{db_name}"
        sh 'bundle exec lux db:am'

        say.green 'Ready at http://lvh.me:3000. Press Ctrl-C to stop.'
        say 'See README.md for routes, AuthCog and frontend components.'
        exec 'bundle', 'exec', 'lux', 's'
      end
    end
  end
end
