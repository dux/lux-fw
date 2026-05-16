namespace :job_runner do
  task :start do
    desc 'Start job runner'
    needs :app

    proc do |_opts|
      jobs_file = './lib/jobs.rb'
      require jobs_file if File.exist?(jobs_file)

      LuxJob.init!
      LuxJob.run
    end
  end

  task :restart do
    desc 'Restart job server'

    proc do |_opts|
      # job-runner-soho_tasks
    end
  end

  task :web do
    desc 'Start job runner web interface on port 3001'
    needs :app
    opt :password, desc: 'Web interface password (positional ok)'

    proc do |opts|
      password = opts[:password] || opts[:args].first
      error 'Usage: lux job_runner:web <password>' unless password

      jobs_file = './lib/jobs.rb'
      require jobs_file if File.exist?(jobs_file)

      require_relative 'lib/lux_job_web'
      LuxJobWeb.password = password
      puts 'Starting LuxJob web interface on http://localhost:3001'
      puts "Password: #{password}"
      LuxJobWeb.run!
    end
  end
end
