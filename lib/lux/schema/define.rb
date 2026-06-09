# Schema definition DSL.
# Accepts a block of field declarations and returns hash of parsed rules.

require 'set'
require 'json'

module Lux
  class Schema
    class Define
      attr_reader :db_rules

      def initialize rules = nil, &block
        @db_rules = []
        @rules    = rules || {}
        instance_exec(&block) if block
      end

      def rules
        @rules.dup
      end

      private

      # used in dsl to define schema field options
      def set field, *args, &block
        raise "Field name not given (Lux::Schema)" unless field

        opts  = parse_args args
        field = field.to_s

        # bang suffix defines block type for all fields in the block
        if field.include?('!')
          return define_block_type(field, &block)
        end

        # question mark suffix makes field optional
        field = parse_field_name field, opts

        resolve_type opts

        # inline block defines a nested model schema
        if block_given?
          opts[:type]  = :model
          opts[:model] = Lux.schema(&block)
        end

        opts[:type] = opts[:type].to_s.downcase.to_sym
        opts[:description] = opts.delete(:desc) unless opts[:desc].nil?

        validate_opts opts

        field = field.to_sym
        db(:add_index, field) if opts.delete(:index)

        @rules[field] = opts
      end

      # pass values for db_schema only
      # db :timestamps
      # db :add_index, :code -> t.add_index :code
      def db *args
        @db_rules.push args
      end

      # reference a registered/stored schema by name inside a field declaration:
      #   user schema(:user)   -> field validated by the :user schema
      # checks API-registered refs first, then global named schemas (raises if none)
      def schema name
        Lux::Schema::REFS[name.to_s.underscore] || Lux.schema(name)
      end

      # if method undefined, call set method
      # age Integer -> set :age, type: :integer
      def method_missing field, *args, &block
        set field, *args, &block
      end

      # --- argument parsing ---

      def parse_args args
        if args.first.is_hash?
          opts = args.first || {}
        else
          opts = args[1] || {}
          opts[:type] ||= args[0]
        end

        opts[:type] = :string if opts[:type].nil?
        opts
      end

      def parse_field_name field, opts
        if field.include?('?')
          field = field.sub('?', '')
          opts[:required] = false
        end

        opts[:required] = opts.delete(:req) unless opts[:req].nil?
        opts[:required] = true if opts[:required].nil?

        field
      end

      # --- type resolution ---

      def define_block_type field, &block
        raise ArgumentError, 'If you use ! you have to provide a block' unless block

        field = field.sub('!', '')
        @block_type = field.to_sym
        instance_exec(&block)
        @block_type = nil
      end

      def resolve_type opts
        # bare Array or Set class -> array of strings
        if opts[:type] == Array || opts[:type] == Set
          opts[:type]  = :string
          opts[:array] = true
        end

        # Array[:type] -> typed array
        if opts[:type].is_a?(Array)
          opts[:type]  = opts[:type].first
          opts[:array] = true
        end

        # Set[:type] -> typed array (no duplicates)
        if opts[:type].is_a?(Set)
          opts[:type]  = opts[:type].to_a.first
          opts[:array] = true
        end

        # block type override (integer! do ... end)
        opts[:type] = @block_type if @block_type

        # boolean variants
        if opts[:type].is_a?(TrueClass) || opts[:type] == :true
          opts[:required] = false
          opts[:default]  = true
          opts[:type]     = :boolean
        elsif opts[:type].is_a?(FalseClass) || opts[:type] == :false || opts[:type] == :boolean
          opts[:required] = false
          opts[:default]  = false if opts[:default].nil?
          opts[:type]     = :boolean
        end

        # model / schema reference
        if opts[:type].is_a?(Lux::Schema)
          opts[:model] = opts.delete(:type)
        end
        opts[:model] = opts.delete(:schema) if opts[:schema]
        opts[:type]  = :model if opts[:model]
      end

      def validate_opts opts
        type = Lux::Type.load opts[:type]
        opts.keys.each do |key|
          type.allowed_opt?(key) { |err| raise ArgumentError, err }
        end
      end
    end
  end
end
