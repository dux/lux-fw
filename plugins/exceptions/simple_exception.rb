module SimpleException
  extend self

  ERROR_FOLDER ||= './log/exceptions'

  def log exception
    return if Lux.env         == 'test'
    # return if exception.class == LocalRaiseError
    return unless Lux.current

    history = exception.backtrace || []
    history = history
      .map{ |el| el.sub(Lux.root.to_s, '') }
      .join("\n")

    data = '%s in %s (user: %s)' % [exception.class, Lux.current.request.url, (Lux.current.var.user.email rescue 'guest')]
    data = [data, exception.message, history].join("\n\n")
    key  = Digest::SHA1.hexdigest history

    folder = Lux.root.join('log/exceptions').to_s
    Dir.mkdir(folder) unless Dir.exists?(folder)

    File.write("#{folder}/#{key}.txt", data)

    key
  end

  def list
    error_files = Dir['%s/*.txt' % ERROR_FOLDER].sort_by { |x| File.mtime(x) }.reverse

    error_files.map do |file|
      last_update = (Time.now - File.mtime(file)).to_i

      age = if last_update < 60
        '%s sec ago' % last_update
      elsif last_update < 60*60
        '%s mins ago' % (last_update/60).to_i
      elsif last_update < 60*60*24
        '%s hours ago' % (last_update/(60*60)).to_i
      else
        '%s days ago' % (last_update/(60*60*24)).to_i
      end

      {
        file: file,
        last_update: last_update,
        desc: File.read(file).split("\n").first,
        code: file.split('/').last.split('.').first,
        age: age
      }
    end
  end

  def get code
    for el in list
      return el if el[:code] == code
    end
  end

  def clear
    system 'rm -rf "%s"' % ERROR_FOLDER
  end
end

