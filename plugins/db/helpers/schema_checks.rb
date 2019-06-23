# inits and saves postgre
#   string and integer arrays
#   hstore as hash with indifferent access to keys

module Sequel::Plugins::LuxInitAndSaveSchemaCheck
  module ClassMethods
  end

  module DatasetMethods
  end

  module InstanceMethods
    def validate
      for field in columns
        schema = db_schema[field]

        # alert, no trim on to big field length
        if schema[:max_length] && self[field] && self[field].length > schema[:max_length]
          msg = 'Field "%s" max length is %s, got %d' % [field, schema[:max_length], self[field].length]
          errors.add(field, msg)
        end
      end

      super
    end

    # set right values on
    # def after_initialize
    #   new_vals = {}
    #   # DB.extension :connection_validator, :pg_array, :pg_json
    #   db_schema.each do |field, schema|
    #     type = schema[:db_type]

    #     if type.include?('[]') && ![Array, Sequel::Postgres::PGArray].include?(self[field].class)
    #       data = self[field].to_s.gsub(/^\{|\}$/, '').split(',')
    #       data = data.map(&:to_i) if schema[:type] == :integer
    #       self[field] = data
    #     elsif type == 'jsonb' && self[field].class != Sequel::Postgres::JSONBHash
    #       self[field] = HashWithIndifferentAccess.new(JSON.load(self[field]) || {})
    #     end
    #   end

    #   super
    # end

    def before_save
      @_array_hash_cache_fields = {}

      db_schema.each do |field, schema|
        if schema[:db_type].include?('[]')
          @_array_hash_cache_fields[field] = self[field].dup

          data = self[field].to_a
          data = data.map(&:to_i) if schema[:type] == :integer

          db_data = data.to_json
          db_data[0,1] = '{'
          db_data[-1,1] = '}'
          self[field] = db_data
        elsif ['json', 'jsonb'].index(schema[:db_type])
          @_array_hash_cache_fields[field] = self[field].dup

          # we use this to convert symbols in keys to strings
          self[field] = JSON.load(self[field].to_json).to_json
        elsif schema[:db_type] == 'boolean'
          self[field] = false if self[field] == 0
          self[field] = true  if self[field] == 1
        end
      end

      super
    end

    def after_save
      @_array_hash_cache_fields.each { |k, v| self[k] = v }

      super
    end
  end

end

Sequel::Model.plugin :lux_init_and_save_schema_check
