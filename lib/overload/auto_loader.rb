class String
  def constantize
    Object.const_get('::'+self)
  end
end

class Object
  def self.const_missing klass
    file  = klass.to_s.tableize.singularize
    paths = [
      'models',
      'lib',
      'vendor',
      file.split('_').last.pluralize
    ].map  { |it| './app/%s/%s.rb' % [it, file] }

    klass_file = paths.find { |it| File.exist?(it) } or
      raise NameError.new('Can not find and autoload class "%s", looked in %s' % [klass, paths.map{ |it| "\n#{it}" }.join('')])

    # puts '* autoload: %s from %s' % [file, klass_file]

    require klass_file

    Object.const_get(klass)
  end
end

