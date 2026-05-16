require 'pathname'

define :new do
  desc 'Create new lux application (lux new APP_NAME)'

  proc do |opts|
    app_folder = opts[:args].first
    error 'Usage: lux new APP_NAME' unless app_folder
    error 'Folder allready exists' if Dir.exist?(app_folder)

    Dir.mkdir(app_folder)

    demo_path = Pathname.new(__dir__).join('../../misc/demo').to_s

    sh "rsync -a -v --ignore-existing '#{demo_path}/' ./#{app_folder}"

    Dir.chdir(app_folder) do
      sh 'bundle install'
      sh 'bundle exec lux_assets install'
    end

    puts
    say.green 'Success! now:'
    puts "cd #{app_folder}"
    puts 'lux s'
  end
end
