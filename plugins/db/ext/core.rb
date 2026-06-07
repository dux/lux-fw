# http://ricostacruz.com/cheatsheets/sequel.html
# http://sequel.jeremyevans.net/rdoc/files/doc/model_plugins_rdoc.html

Sequel::Model.plugin :dirty

class Sequel::Model
  module ClassMethods
    def find_by what
      where(what).first
    end

    # active record like define scope
    # http://sequel.jeremyevans.net/rdoc/classes/Sequel/Model/ClassMethods.html
    def scope name, body=nil, &block
      block ||= body
      dataset_module{define_method(name, &block)}
    end

    # instance scope, same as scope but runs on instance
    # iscope(:notes)   { Note.where(created_by: ref) }
    def iscope name, body=nil, &block
      block ||= body
      define_method(name, &block)
    end

    def first_or_new filter
      object = where(filter).first || new(filter)
      yield object if block_given? && object.new?
      object
    end

    def first_or_create filter
      object = where(filter).first || new(filter)
      if object.new?
        yield object if block_given?
        object.save
      end
      object
    end
  end

  module InstanceMethods
    # primary key accessor; all lux models key on the :ref column
    def ref
      self[:ref]
    end

    def key namespace = nil
      v = "%s/%s" % [self.class, self[:ref]]
      namespace ? "#{v}/#{namespace}" : v
    end

    def cache_key namespace = nil
      key =
      if self[:updated_at]
        "%s/%s-%s" % [self.class, self[:ref], self[:updated_at].to_f]
      else
        self.key
      end

      namespace ? [key, namespace].join('/') : key
    end

    def attributes
      columns.each_with_object({}) do |el, ret|
        ret[el.to_s] = send(el)
      end
    end
    alias :to_h :attributes

    def creator
      v = self[:creator_ref]
      v && defined?(User) ? User.find(v) : nil
    end

    def updater
      v = self[:updater_ref]
      v && defined?(User) ? User.find(v) : nil
    end

    # has?(:name, "Name is not defined") -> errors.add("Name is not defined")
    # has?(:name) -> false
    def has?(*args)
      if args[1] && args[1].kind_of?(String)
        unless self[args[0]].present?
          errors.add(args[0], args[1])
          return false
        end
        return true
      end
      args.each { |el| return false unless self[el].present? }
      true
    end

    def unique?(field)
      check = self.class.where(field => self[field])
      check = check.exclude(ref: self[:ref]) if self[:ref]
      check.empty?
    end

    def save!
      save validate: false
    end

    def slice *args
      args.inject({}) { |t, el| t[el] = self.send(el); t }
    end

    # Build a new record of `name` already linked back to self via the
    # caller's *_ref column (whichever shape RefLinker detects).
    #   @deal.init(:task) -> Task.new(deal_ref: @deal.ref)
    def init name, fields = {}
      target = name.to_s.classify.constantize
      shape  = Sequel::Plugins::RefLinker.detect(target, self.class)
      fields[shape[:columns][0]] = self[:ref] if shape && shape[:kind] == :scalar
      target.new(fields)
    end

    def merge hash
      for key, val in hash
        m = "#{key}="
        send m, val if respond_to?(m)
      end
    end

    # on_change :ord do |prev_val, next_val| ...
    def on_change field
      if column_changed?(field)
        yield *column_change(field)
      end
    end
  end
end
