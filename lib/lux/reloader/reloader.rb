# Reloads source files modified since the last check.
# Called per-request in dev (Lux.mode.reload? && Lux.runtime.web?) and explicitly
# from the console via `reload!`.
module Lux
  module Reloader
    extend self

    @last_check ||= Time.now

    def run source = nil
      watched_files = $LOADED_FEATURES
        .reject { |f| f.include?('/.') }
        .select { |f| File.exist?(f) && File.mtime(f) > @last_check }

      if watched_files.first
        for file in watched_files
          Lux.log ' Reloaded: %s' % file.sub(Lux.root.to_s, '.').colorize(:yellow)
          load file
        end
      else
        Lux.info 'No code changes found' if Lux.runtime.cli?
      end

      if source == :cli
        Lux::Current.new('/')

        if File.exist?('./config/console.rb')
          load './config/console.rb'
        end
      end

      @last_check = Time.now
    end
  end
end
