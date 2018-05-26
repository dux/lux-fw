Lux.app do
  def lux_static_files_plug
    file = Lux::Current::StaticFile.new(Lux.current.request.path)
    return false unless file.is_static_file?
    file.deliver
    true
  end

  def lux_redirect_to_host_plug
    host = ENV['HTTP_HOST'] || ENV['HOST'] || raise("ENV['HOST'] not defined")

    unless request.url.include?(host)
      redirect host + request.path
    end
  end
end
