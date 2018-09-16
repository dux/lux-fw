# frozen_string_literal: true

# $LOADED_FEATURES.select{ |f| f.index('/app/') || f.index('/lux/') }

require 'yaml'

module Lux::Config
  extend self

  # if we have errors in module loading, try to load them one more time
  @@mtime_cache  ||= {}
  @@load_info    ||= nil

  # requires all files recrusive in, with spart sort
  def require_all files
    files = files.to_s
    files += '/*' unless files.include?('*')

    file_errors = []
    glob = `echo #{files} #{files}/* #{files}/*/*  #{files}/*/*/* #{files}/*/*/*/* #{files}/*/*/*/*/* |tr ' ' '\n' | grep .rb`.split("\n")

    glob.select{ |o| o.index('.rb') }.map{ |o| o.split('.rb')[0]}.each do |ruby_file|
      require ruby_file
    end
  end

  # preview config in development
  def show_config
    for k,v in Lux.config
      next if v.kind_of?(Hash)
      puts "* config :#{k} = #{v.kind_of?(Hash) ? '{...}' : v}"
    end
  end

  # gets last 2 changed files
  def get_last_changed_files dir
    `find #{dir} -type f -name "*.rb" -print0 | xargs -0 stat -f"%m %Sm %N" | sort -rn | head -n2`.split("\n").map{ |it| it.split(/\s+/).last }
  end

  def live_require_check!
    files  = get_last_changed_files './app'
    files += get_last_changed_files '%s/lib' % Lux.fw_root
    files += get_last_changed_files '%s/plugins' % Lux.fw_root

    for file in files
      @@mtime_cache[file] ||= 0
      file_mtime = File.mtime(file).to_i
      next if @@mtime_cache[file] == file_mtime

      Lux.log ' Reloaded: %s' % file.split(Lux.root.to_s).last.red if @@mtime_cache[file] > 0
      @@mtime_cache[file] = file_mtime
      load file
    end

    true
  end

  def ram
    `ps -o rss -p #{$$}`.chomp.split("\n").last.to_i / 1000
  end

  def start! start=nil
    set_default_vars

    return @@load_info unless start

    speed = ((Time.now - start)*1000).round.to_s.sub(/(\d)(\d{3})$/,'\1s \2')+'ms'

    production_mode = true

    production_opts = [
      [:compile_assets,     false],
      [:auto_code_reload,   false],
      [:show_server_errors, false],
      [:log_to_stdout,      false],
    ]

    opts = production_opts.map do |key, production_value|
      config_test     = Lux.config(key)
      config_ok       = production_value == config_test
      production_mode = false unless config_ok

      data = "#{key} (%s)" % [config_test ? :yes : :no]
      config_ok ? data : data.yellow
    end

    puts @@load_info = '* Config: %s' % opts.join(', ')

    mode = production_mode ? 'production'.green : 'development'.yellow

    "* Lux loaded #{mode} mode in #{speed.to_s.white}, uses #{ram.to_s.white} MB RAM with total of #{Gem.loaded_specs.keys.length.to_s.white} gems in spec".tap do |it|
      @@load_info += "\n#{it}"
    end
  end

  def set_default_vars
    # Show server errors to a client
    Lux.config.show_server_errors ||= false

    # Log debug output to stdout
    Lux.config.log_to_stdout ||= false

    # Automatic code reloads in development
    Lux.config.auto_code_reload ||= false

    # Default error logging
    Lux.config.on_error ||= proc do |error|
      Lux::Error.dev_log error
      raise error
    end

    # Default mail logging
    Lux.config.on_mail ||= proc do |mail|
      Lux.logger(:email).info "[#{self.class}.#{@_template} to #{mail.to}] #{mail.subject}"
    end

    # deafult host is required
    unless Lux.config.host.to_s.include?('http')
      raise 'Invalid "Lux.config.host"'
    end
  end

end

class Object
  def reload!
    Lux::Config.live_require_check!
  end
end