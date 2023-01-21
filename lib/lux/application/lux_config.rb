$live_require_check = Time.now

Lux.config.on_code_reload do |source = nil|
  watched_files = $LOADED_FEATURES
    .reject { |f| f.include?('/.') }
    .select { |f| File.exist?(f) && File.mtime(f) > $live_require_check }

  if watched_files.first
    for file in watched_files
      Lux.log ' Reloaded: %s' % file.sub(Lux.root.to_s, '.').yellow
      load file
    end
  else
    Lux.info 'No code changes found' if Lux.env.cli?
  end

  if source == :cli
    Lux::Current.new('/')

    if File.exist?('./config/console.rb')
      load './config/console.rb'
    end
  end

  $live_require_check = Time.now
end
