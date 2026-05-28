require 'fileutils'

# Scaffold a new Lux application from the skeleton in assets/new_app.
task :new do
  desc 'Create a new Lux application'
  example 'new my-app'

  proc do |opts|
    name = opts[:args].first
    raise Hammer::Error, 'usage: lux new APP_NAME' unless name

    target = File.expand_path(name)
    raise Hammer::Error, "path already exists: #{name}" if File.exist?(target)

    app_under = File.basename(name).gsub(/[^a-zA-Z0-9]+/, '_').downcase
    app_name  = app_under.split('_').map(&:capitalize).join(' ')
    secret    = Lux::Utils::Crypt.random(128)
    vars      = { 'app' => app_under, 'App' => app_name, 'secret' => secret }

    skeleton = Lux.fw_root.join('assets/new_app').to_s

    Dir.glob("#{skeleton}/**/*", File::FNM_DOTMATCH).sort.each do |src|
      base = File.basename(src)
      next if File.directory?(src) || base == '.' || base == '..'

      rel  = src.sub("#{skeleton}/", '')
      dst  = File.join(target, rel)
      data = File.read(src).gsub(/\{\{(\w+)\}\}/) { vars[$1] || $~[0] }

      FileUtils.mkdir_p(File.dirname(dst))
      File.write(dst, data)
      puts '  create  %s' % "#{name}/#{rel}".colorize(:green)
    end

    puts
    puts 'Created %s. Next:' % name.colorize(:yellow)
    puts '  cd %s' % name
    puts '  bundle install'
    puts '  createdb %s_development' % app_under
    puts '  lux db:am          # create tables from model schemas'
    puts '  lux s              # start the server on http://lvh.me:3000'
  end
end
