# def foo opts = {}
#   @opts = StructOpts opts, foo: 123, bar: nil
#   ...

module StructOpts
  OPTS ||= {}

  def self.call vars, opts
    name   = '%sStructOpts' % self.class
    struct = StructOpts::OPTS[name] ||= Struct.new name, *opts.keys
    ivars  = struct.new

    vars.each do |k, v|
      ivars.send '%s=' % k, v
    end

    opts.each do |k, v|
      if vars[k].empty?
        ivars.send '%s=' % k, v
      end
    end

    ivars
  end
end

def StructOpts vars, opts
  StructOpts.call vars, opts
end

