# http://ricostacruz.com/cheatsheets/sequel.html
# http://sequel.jeremyevans.net/rdoc/files/doc/model_plugins_rdoc.html

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
    # iscope(:notes)   { Note.where(created_by:id) }
    def iscope name, body=nil, &block
      block ||= body
      define_method(name, &block)
    end

    def first_or_new filter
      object = where(filter).first || new(filter)
      yield object if block_given? && !object.id
      object
    end

    def first_or_create filter, &block
      object = first_or_new(filter, &block)
      yield object if block_given?
      object.save
      object
    end
  end

  module InstanceMethods
    def key namespace = nil
      v = "%s/%s" % [self.class, self[:ref] || self[:id]]
      namespace ? "#{v}/#{namespace}" : v
    end

    def cache_key namespace = nil
      key =
      if self[:updated_at]
        "%s/%s-%s" % [self.class, self.id, self[:updated_at].to_f]
      else
        self.key
      end

      namespace ? [key, namespace].join('/') : key
    end

    def attributes
      {}.tap do |ret|
        for el in columns
          ret[el.to_s] = send(el.to_s)
        end
      end
    end
    alias :to_h :attributes

    def creator
      v = self[:creator_ref] || self[:created_by_ref] || self[:created_by]
      v ? User.find(v) : nil
    end

    def updater
      v = self[:updater_ref] || self[:updated_by_ref] || self[:updated_by]
      v ? User.find(v) : nil
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
      self.class.where(field => self[field]).exclude(ref: self[:ref]).count == 0
    end

    def save!
      save validate: false
    end

    def slice *args
      args.inject({}) { |t, el| t[el] = self.send(el); t }
    end
    alias :pluck :slice

    # @deal.init(:task) -> Task.new(deal_ref: 'abc')
    def init name, fields={}
      fields['%s_ref' % self.class.to_s.tableize.singularize] = self[:ref]
      name.to_s.classify.constantize.new(fields)
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

  module DatasetMethods
    def refs cnt = nil
      select(:ref).limit(cnt || 1000).all.map(&:ref)
    end

    def latest
      order(Sequel.desc(:updated_at))
    end
  end
end


