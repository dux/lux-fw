namespace :nginx do
  desc 'Generate sample config'
  task :generate do
    command = ARGV[1]

    ROOT   = Dir.pwd
    FOLDER = Dir.pwd.split('/').last

    @target_conf = '/etc/nginx/sites-enabled/%s.conf' % FOLDER
    conf  = Lux.fw_root.join('misc/nginx.conf').read
    conf = conf.gsub(/`([^`]+)`/) { `#{$1}`.chomp }
    conf = conf.gsub('$ROOT', ROOT)
    conf = conf.gsub('$FOLDER', FOLDER)
    puts conf

    case command
      when 'show'
        puts build_conf
      when 'install'
        File.write './tmp/nginx.conf', build_conf
        puts '# run this manualy'
        puts
        puts 'sudo cp ./tmp/nginx.conf %s && sudo nginx -t' % @target_conf
      else
        puts ' show      # show rendered config'
        puts ' install   # install config/nginx.conf to %s' % @target_conf
    end
  end

  desc 'Edit nginx config'
  task :edit do
    folder = Dir.pwd.split('/').last

    run 'sudo vim /etc/sites-enabled/%s.conf' % folder
  end
end

