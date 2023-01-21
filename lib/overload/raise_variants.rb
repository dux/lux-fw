class Object
  # raise object
  def r what
    if what.is_a?(Method)
      rr [:source_location, what.source_location.join(':')]
    else
      rr what
    end

    raise StandardError.new(what)
  end

  # better console log dump
  def rr what
    klass = what.class
    klass = '%s at %s' % [klass, what.source_location.join(':').sub(Lux.root.to_s, '.')] if klass == Method
    from = caller[0].include?('raise_variants.rb') ? caller[1] : caller[0]
    from = from.sub(Lux.root.to_s+'/', './').split(':in ').first
    ap ['--- START (%s) %s - %s ---' % [klass, from, Lux.current.request.url], what, '--- END ---']
  end

  # unique methods for object
  # includes methods from modules
  def r? object
    dump = []

    dump.push 'Class: %s' % object.class

    instance_unique = object.methods - object.class.ancestors[0].instance_methods
    class_unique    = object.methods

    object.class.ancestors.drop(1).each do |_|
      class_unique -= _.instance_methods

      if _.class != Module
        dump.push 'Parent Class: %s' % _
        break
      end
    end

    dump.push ['Instance uniqe', instance_unique.sort] if instance_unique[0]
    dump.push ['Uniqe from parent', class_unique.sort.join(', ')]
    dump.push ['Uniqe from parent simple', object.class.instance_methods(false)]

    rr dump
  end
end

###

# if we dont have awesome print in prodction, define mock
method(:ap) rescue Proc.new do
  class Object
    def ap(*args)
      puts args
    end
  end
end.call
