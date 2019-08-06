namespace :nginx do
  desc 'Generate sample config'
  task :generate do
    command = ARGV[1]

    ROOT   = Dir.pwd
    FOLDER = Dir.pwd.split('/').last

    conf  = Lux.fw_root.join('misc/nginx.conf').read
    conf = conf.gsub(/`([^`]+)`/) { `#{$1}`.chomp }
    conf = conf.gsub('$ROOT', ROOT)
    conf = conf.gsub('$FOLDER', FOLDER)
    puts conf
  end

  desc 'Edit nginx config'
  task :edit do
    folder = Dir.pwd.split('/').last

    run 'sudo vim /etc/nginx/sites-enabled/%s.conf' % folder
  end
end

