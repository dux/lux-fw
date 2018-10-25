# frozen_string_literal: true

# $LOADED_FEATURES.select{ |f| f.index('/app/') || f.index('/lux/') }

require 'yaml'

class Lux::Config
  class_callbacks :before_boot, :boot, :after_boot

  boot do
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

    # default event bus error handle
    Lux.config.on_event_bus_error = proc do |error, name|
      Lux.logger(:event_bus).error '[%s] %s' % [name, error.message]
    end

    # app should not start unless config is loaded
    Lux.config.lux_config_loaded = true
  end

  after_boot do
    # deafult host is required
    unless Lux.config.host.to_s.include?('http')
      raise 'Invalid "Lux.config.host"'
    end
  end

  ###

  # if we have errors in module loading, try to load them one more time
  @@mtime_cache  ||= {}
  @@load_info    ||= nil

  class << self
    # requires all files recrusive in, with spart sort
    def require_all files
      files = files.to_s.sub(/\/$/,'')
      raise '* is not allowed' if files.include?('*')

      glob = `echo #{files}/* #{files}/*/*  #{files}/*/*/* #{files}/*/*/*/* #{files}/*/*/*/*/* #{files}/*/*/*/*/*/* |tr ' ' '\n' | grep .rb`.split("\n")
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

    # gets last 3 changed files
    def get_last_changed_files dir
      `find #{dir} -type f -name "*.rb" -print0 | xargs -0 stat -f"%m %Sm %N" | sort -rn | head -n3`.split("\n").map{ |it| it.split(/\s+/).last }
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

    def start!
      c = new
      c.class_callback :before_boot
      c.class_callback :boot
      c.class_callback :after_boot

      start_info $lux_start_time
    end

    def start_info start=nil
      return @@load_info if @@load_info

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

      mode  = production_mode ? 'production'.green : 'development'.yellow
      speed = start ? ((Time.now - start)*1000).round.to_s.sub(/(\d)(\d{3})$/,'\1s \2')+'ms' : '?ms'

      info = []
      info.push '* Config: %s' % opts.join(', ')
      info.push "* Lux loaded #{mode} mode in #{speed.to_s.white}, uses #{ram.to_s.white} MB RAM with total of #{Gem.loaded_specs.keys.length.to_s.white} gems in spec"

      @@load_info = info.join($/)

      puts @@load_info if start
    end
  end

end

class Object
  def reload!
    Lux::Config.live_require_check!
  end
end