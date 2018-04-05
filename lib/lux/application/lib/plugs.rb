class Lux::Application

  def lux_static_files_plug
    file = Lux::Current::StaticFile.new(Lux.current.request.path)
    return false unless file.is_static_file?
    file.deliver
    true
  end

end
