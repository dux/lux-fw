namespace :nginx do
  define :generate do
    desc 'Generate sample config'
    needs :env
    proc do |_opts|
      root   = Dir.pwd
      folder = Dir.pwd.split('/').last

      conf = Lux.fw_root.join('misc/nginx.conf').read
      conf = conf.gsub(/`([^`]+)`/) { `#{$1}`.chomp }
      conf = conf.gsub('$ROOT', root)
      conf = conf.gsub('$FOLDER', folder)
      puts conf
    end
  end

  define :edit do
    desc 'Edit nginx config'
    needs :env
    proc do |_opts|
      folder = Dir.pwd.split('/').last
      sh 'sudo vim /etc/nginx/sites-enabled/%s.conf' % folder
    end
  end
end
