SYSD_DIR = './config/sysd'

LuxCli.class_eval do
  desc :sysd, 'Manage systemd services'
  def sysd action=nil, service=nil
    unless action
      puts "Usage: lux sysd [generate|list|start|stop|restart] [service_name]"
      puts
      puts "Examples:"
      puts "  lux sysd generate          # Generate systemd service config for current app"
      puts "  lux sysd list              # List local services (#{SYSD_DIR})"
      puts "  lux sysd list_all          # List all services"
      puts "  lux sysd start nginx       # Start nginx service"
      puts "  lux sysd stop nginx        # Stop nginx service"
      puts "  lux sysd restart nginx     # Restart nginx service"
      return
    end

    case action
    when 'generate'
      port = service || '3100'
      user = `whoami`.strip
      pwd = Dir.pwd
      bundle_path = `which bundle`.strip

      config = <<~CONFIG
        [Unit]
        Description=Soho tasks (PORT #{port})
        After=network.target

        [Service]
        Type=simple
        User=#{user}
        WorkingDirectory=#{pwd}
        ExecStart=#{bundle_path} exec puma -p #{port}
        PIDFile=#{pwd}/tmp/puma.pid
        Restart=always

        [Install]
        WantedBy=multi-user.target
      CONFIG

      puts config
      puts
      puts "To install this service:".green
      puts "1. Save this config to: /etc/systemd/system/your-app-name.service"
      puts "2. Run: sudo systemctl daemon-reload"
      puts "3. Run: sudo systemctl enable your-app-name"
      puts "4. Run: sudo systemctl start your-app-name"
    when 'list'
      unless Dir.exist?(SYSD_DIR)
        puts "No service directory found at #{SYSD_DIR}".yellow
        return
      end

      service_files = Dir.glob("#{SYSD_DIR}/*.service")

      if service_files.empty?
        puts "No service files found in #{SYSD_DIR}".yellow
        return
      end

      puts "Services in #{SYSD_DIR}:".green
      puts

      service_files.each do |file|
        service_name = File.basename(file, '.service')

        # Check if service is installed
        installed = system("systemctl list-unit-files | grep -q '^#{service_name}.service'", out: File::NULL, err: File::NULL)

        if installed
          # Get service status
          status_output = `systemctl is-active #{service_name} 2>/dev/null`.strip

          status = case status_output
                   when 'active'
                     'running'.green
                   when 'inactive'
                     'stopped'.yellow
                   when 'failed'
                     'failed'.red
                   else
                     status_output
                   end
        else
          status = 'not installed'.gray
        end

        puts "  #{service_name}: #{status}"
      end
    when 'list_all'
      puts "Listing systemd services...".green
      command = "systemctl list-units --type=service --all | grep -v '^  systemd-' | grep '\\.service'"
      Cli.run command
    when 'start'
      Cli.die "Service name required" unless service
      puts "Starting #{service} service...".green
      command = "sudo systemctl start #{service}"
      Cli.run command
      puts "Service #{service} started".green
      Cli.run "sudo systemctl status #{service} --no-pager"
    when 'stop'
      Cli.die "Service name required" unless service
      puts "Stopping #{service} service...".yellow
      command = "sudo systemctl stop #{service}"
      Cli.run command
      puts "Service #{service} stopped".yellow
    when 'restart'
      Cli.die "Service name required" unless service
      puts "Restarting #{service} service...".yellow
      command = "sudo systemctl restart #{service}"
      Cli.run command
      puts "Service #{service} restarted".green
      Cli.run "sudo systemctl status #{service} --no-pager"
    else
      Cli.die "Unknown action: #{action}. Valid actions are: generate, list, list_all, start, stop, restart"
    end
  end
end
