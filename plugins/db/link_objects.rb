module Sequel::Plugins::LuxLinks
  LUX_LINK ||= {}

  module ClassMethods
    # Object.genders
    # @object.gender
    def link name, opts={}
      opts = opts.to_hwia :class, :touch, :polymorphic, :counter, :name, :field

      name_s = name.to_s.singularize
      name_p = name.to_s.pluralize

      klass = opts[:class] ? opts[:class].to_s : name.to_s.singularize.classify

      if opts.counter.class == TrueClass
        opts.counter = '%s_count' % name_p
      end

      opts.field ||= '%s_id' % name_s
      opts.name    = name

      LUX_LINK[to_s] ||= {}
      LUX_LINK[to_s][klass] = opts

      # link :country, class: Country -> many_to_one :country
      if name.to_s == name_s
        class_eval %[
          def #{name_s}
            @#{name_s}_cached ||= #{klass}.find(#{opts.field})
          end
          def #{name_s}=(object)
            @#{name_s}_cached = object
          end
        ]

      # link :cities
      # postgre integer array, has to be in form #{name.singularize}_ids
      # city_ids = [1,2,4]
      # cities -> [<City:1>, <City:2>, <City:4>]
      elsif db_schema["#{name_s}_ids".to_sym]
        # puts "* #{to_s}.link :#{name} -> inline #{name_s}_ids".yellow
        class_eval %[
          def #{name_p}
            return [] if #{name_s}_ids.blank?
            ids = #{name_s}_ids.uniq

            if !ids.first
              []
            elsif !ids[1]
              [#{klass}.find(ids.first)]
            else
              #{klass}.where(Sequel.lit('id in ('+ids.join(',')+')')).all
            end
          end
        ]

      # link :users, class: OrgUser -> OrgUser.where(org_id)
      # elsif opts[:class]
      #   class_eval %[
      #     def #{name_p}
      #       #{comm}
      #     end
        # ]

      # link :countries -> one_to_many :countries
      else
        # one_to_many name, opts
        field = "#{to_s.tableize.singularize}_id"

        if poly = opts[:polymorphic]
          comm = "#{klass}.where(model_type: '#{to_s}', model_id: id).default"
        elsif klass.constantize.db_schema[field.to_sym]
          comm = "#{klass}.where(#{field}:id).default"
        else
          # we have a link table
          cname = klass[0,1] > to_s[0,1] ? "#{to_s}#{klass}" : "#{klass}#{to_s}"

          die "Link field/table not found for #{to_s}.link :#{name}" unless const_defined?(cname)

          comm  = "#{klass}.default.xwhere('id in (select #{klass.tableize.singularize}_id from #{cname.tableize} where #{to_s.tableize.singularize}_id=?)', id)"
          # puts "* #{to_s}.link :#{name} -> #{comm}"
        end

        class_eval %[
          def #{name_p}
            #{comm}
          end
        ]
      end
    end
  end

  module InstanceMethods
    def after_save
      super
      _lux_link_callbaks
    end

    def after_destroy
      super
      _lux_link_callbaks
    end

    def _lux_link_callbaks
      for klass, opts in LUX_LINK[self.class.to_s].or({})
        # Task.link :card, touch: true
        #   will touch @task.card (to clear caches) when @task changes
        # if opts.touch
        #   send(opts.name).touch
        # end

        # Asset.link :card, counter: true
        #   will update cache on @card.assets_count when @card.asset changes
        if counter_name = opts.counter
          parent = send opts.name
          parent.send counter_name, self.class.where(opts.field => id).count
          parent.save
        end
      end
    end
  end
end

Sequel::Model.plugin :lux_links