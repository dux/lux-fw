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
      where(filter).first || new(filter)
    end

    def first_or_create filter
      where(filter).first || create(filter)
    end
  end

  module InstanceMethods
    def cache_key
      "#{self.class}/#{id}"
    end

    def attributes
      ret = {}
      for el in columns
        ret[el.to_s] = send(el.to_s) rescue '-'
      end
      ret
    end

    def touch
      self[:updated_at] = Time.now.utc
      save columns: [:updated_at]
    end

    def to_h
      ret = {}
      for el in self.keys
        ret[el] = send el
      end
      ret
    end

    def creator
      self[:created_by] ? User.find(self[:created_by]) : nil
    end

    def updater
      self[:updated_by] ? User.find(self[:updated_by]) : nil
    end

    def parent_model
      model_type.constantize.find(model_id)
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
      select(field).xwhere('id<>?', id).count == 0
    end

    def save!
      save
    end
  end

  module DatasetMethods
  end
end


