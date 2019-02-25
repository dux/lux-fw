require 'pathname'

LuxCli.class_eval do
  desc 'new APP_NAME', 'Creates new lux application'
  def new app_folder
    Cli.die 'Folder allready exists' if Dir.exist?(app_folder)

    Dir.mkdir(app_folder)

    demo_path = Pathname.new(__dir__).join('../../misc/demo').to_s

    Cli.run "rsync -a -v --ignore-existing '#{demo_path}/' ./#{app_folder}"

    Dir.chdir(app_folder) do
      Cli.run "bundle install"
      Cli.run "bundle exec lux_assets install"
    end

    puts
    puts 'Success! now:'.green
    puts 'cd %s' % app_folder
    puts 'lux s'
  end
end
