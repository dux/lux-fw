namespace :job_runner do
  desc 'Start job runner'
  task start: :app do
    jobs_file = './lib/jobs.rb'
    if File.exist?(jobs_file)
      require jobs_file
    end
    LuxJob.init!
    LuxJob.run
  end

  desc 'Start job runner web interface on port 3001'
  task :web, [:password] => :app do |_, args|
    unless args[:password]
      puts "Usage: rake job_runner:web[password]"
      exit 1
    end

    jobs_file = './lib/jobs.rb'
    if File.exist?(jobs_file)
      require jobs_file
    end
    require_relative '../lib/lux_job_web'
    LuxJobWeb.password = args[:password]
    puts "Starting LuxJob web interface on http://localhost:3001"
    puts "Password: #{args[:password]}"
    LuxJobWeb.run!
  end
end
