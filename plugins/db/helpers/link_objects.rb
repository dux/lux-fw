# @notes.preload(:bucket)

# class Array
#   def preload(name)
#     field = "#{name.to_s.singularize}_id".to_sym
#     ids = self.map{ |o| o[field] }.uniq
#     buckets = name.to_s.classify.constantize.where(id:ids).to_a

#     for o in self
#       o.send "#{name}=", buckets.select{ |el| o.id==el.id }[0]
#     end
#   end
# end

class Sequel::Model
  module ClassMethods

    # Object.genders
    # @object.gender
    def link name, opts={}
      name_s = name.to_s.singularize
      name_p = name.to_s.pluralize

      raise 'Please use enums plugin' if opts[:collection]

      klass = opts[:class] ? opts[:class].to_s : name.to_s.singularize.classify

      # link :country, class: Country -> many_to_one :country
      if name.to_s == name_s
        class_eval %[
          def #{name_s}
            @#{name_s}_cached ||= #{klass}.find(#{name_s}_id)
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

      # link :countries -> one_to_many :countries
      else
        # one_to_many name, opts
        field = "#{to_s.tableize.singularize}_id"

        if klass.constantize.db_schema[field.to_sym]
          comm = "#{klass}.where(#{field}:id).default"
        else
          # we have a link table
          cname = klass[0,1] > to_s[0,1] ? "#{to_s}#{klass}" : "#{klass}#{to_s}"
          comm  = "#{klass}.xwhere('id in (select #{klass.tableize.singularize}_id from #{cname.tableize} where #{to_s.tableize.singularize}_id=?)', id)"
          puts "* #{to_s}.link :#{name} -> #{comm}"
        end

        class_eval %[
          def #{name_p}
            #{comm}
          end
        ]
      end
    end
  end
end


