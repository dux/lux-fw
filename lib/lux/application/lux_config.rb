Lux.config.on_code_reload do
  $live_require_check ||= Time.now

  watched_files = $LOADED_FEATURES
    .reject { |f| f.include?('/.') }
    .select { |f| File.exist?(f) && File.mtime(f) > $live_require_check }

  for file in watched_files
    Lux.log ' Reloaded: %s' % file.sub(Lux.root.to_s, '.').yellow
    load file
  end

  $live_require_check = Time.now
end
