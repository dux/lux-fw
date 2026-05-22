module Lux
  # define or look up a schema
  #   Lux.schema(:blog) { ... }            - define
  #   Lux.schema(:blog, type: :model) { }  - define with opts
  #   Lux.schema(:blog)                    - lookup, raises if missing
  #   Lux.schema(type: :model)             - find all schemas matching opt
  def schema name = nil, opts = nil, &block
    klass = name.to_s.classify if name && !name.is_hash?

    if block_given?
      Lux::Schema.new(klass, opts, &block)
    else
      if name.is_hash?
        out = []
        Lux::Schema::SCHEMA_STORE.values.each do |schema|
          if schema.opts[name.keys.first] == name.values.first
            out.push schema.klass
          end
        end
        out
      else
        Lux::Schema::SCHEMA_STORE[klass] || raise('Schema "%s" not found' % klass)
      end
    end
  end

  # same as schema but returns nil if not found
  def schema? name
    klass = name.to_s.classify if name
    Lux::Schema::SCHEMA_STORE[klass] if klass
  end

  # array of database fields, Sequel-compatible
  def db_schema name
    Lux.schema(name).db_schema
  end
end
