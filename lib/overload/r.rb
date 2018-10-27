class LocalRaiseError < StandardError
end

class Object
  # raise object
  def r what
    opath = what.class.ancestors
    out   = opath.join("\n> ")

    data = what.is_a?(Hash) ? JSON.pretty_generate(what) : what.ai(plain:true)
    out = [data, out, ''].join("\n\n-\n\n")

    # unique_methods = what.methods - what.class.ancestors[0].instance_methods
    # raise unique_methods

    raise LocalRaiseError.new out
  end

  # better console log dump
  def rr what
    src = caller[0].sub(Lux.root.to_s+'/', '').sub(Lux.fw_root.to_s, 'lux-fw').split(':in `').first
    ap ['--- START (%s) %s ---' % [what.class, src], what, '--- END ---']
  end

  # unique methods for object
  # includes methods from modules
  def rm object
    dump = []

    dump.push ['Class', object.class]

    instance_unique = object.methods - object.class.ancestors[0].instance_methods
    class_unique    = object.methods

    object.class.ancestors.drop(1).each do |_|
      class_unique -= _.instance_methods

      if _.class != Module
        dump.push ['Parent Class', _]
        break
      end
    end

    dump.push ['Instance uniqe', instance_unique.sort] if instance_unique[0]
    dump.push ['Uniqe from parent', class_unique.sort]
    dump.push ['Uniqe from parent simple', object.class.instance_methods(false)]

    r dump
  end

  def rr! what
    print "\e[H\e[2J\e[3J" # clear osx screen :)
    rr what
  end

  # show method info
  # show User, :secure_hash
  def rr? instance, m
    el = instance.class.instance_method(m)
    puts el.source_location.join(':').yellow
    puts '-'
    puts el.source if el.respond_to?(:source)
    nil
  end
end