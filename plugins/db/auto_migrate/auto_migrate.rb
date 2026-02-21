# https://github.com/jeremyevans/sequel/blob/master/doc/schema_modification.rdoc
#
# Auto-migrates database schema based on Typero model definitions.
# Triggered by Typero sequel adapter when ENV['DB_MIGRATE'] == 'true'.
#
# Usage: rake db:am (sets DB_MIGRATE=true before loading models)

class AutoMigrate
  class << self
    def apply_schema klass
      klass = klass.constantize if klass.class == String
      schema = Typero.schema(klass)

      am = new klass.db
      am.table klass, schema.rules do |f|
        for args in schema.db_schema
          if args.first != :db_rule!
            f.send args[1], args[0], args[2]
          else
            args.shift
            f.db_rule *args
          end
        end
      end

      klass.db.schema(klass.to_s.tableize, reload: true)
      klass
    end
  end

  ###

  attr_accessor :fields, :db

  def initialize db_name = nil
    self.db = db_name if db_name
  end

  def db
    @db || DB
  end

  # create table and schema migrate, if able
  def table table_name, opts = {}
    @fields     = {}
    @table_name = table_name.to_s.tableize.to_sym
    @opts = opts || {}

    # create table unless it exists
    unless self.db.table_exists?(@table_name.to_s)
      # http://sequel.jeremyevans.net/rdoc/files/doc/schema_modification_rdoc.html

      self.db.create_table(@table_name) do
        String :ref, primary_key: true
      end
    end

    @db_indexes = self.db.fetch(%[SELECT indexname FROM pg_indexes WHERE tablename = '#{@table_name}';])
      .to_a
      .map{ _1[:indexname]}
      .reject{ _1.end_with?('_pkey') }
      .map{ _1.sub(/_index$/, '').sub('%s_' % @table_name, '') }

    @object = self.db.schema(@table_name).to_h

    # apply schema if one given
    if block_given?
      yield self
      self.fix_fields
      self.update
    end
  end

  def transaction_do text
    begin
      self.db.run 'BEGIN; %s ;COMMIT;' % text
    rescue
      puts caller[1].colorize(:red)
      puts text.colorize(:yellow)
      raise $!
    end
  end

  def enable_extension name
    self.db.run 'CREATE EXTENSION IF NOT EXISTS %s;' % name
  end

  def extension name
    unless self.db["SELECT extname FROM pg_extension where extname='#{name}'"].to_a.first
      log_run 'CREATE EXTENSION %s' % name
    end
  end

  def log_run what
    puts ' %s' % what.colorize(:green)
    transaction_do what
  end

  def fix_fields
    for vals in @fields.values
      type = vals[0]
      opts = vals[1]

      opts[:limit]   ||= 255 if type == :string
      opts[:default] ||= false if type == :boolean
      opts[:null]      = true unless opts[:null].class.name == 'FalseClass'
      opts[:array]   ||= false
      opts[:unique]  ||= false
      opts[:default]   = [] if opts[:array]
    end
  end

  def get_db_column_type field
    type, opts = @fields[field]
    db_type = type
    db_type = "varchar(#{opts[:limit] || 255})" if type == :string
    db_type = :timestamp if type == :timestamp

    if opts[:array]
      db_type = '%s[]' % db_type
    end

    db_type
  end

  def update
    puts "Table #{@table_name.to_s.colorize(:yellow)}, #{@fields.keys.length} fields in #{self.db.uri.split('/').last}"

    # remove extra fields
    for field in (@object.keys - @fields.keys - [:id, :ref])
      was_name = @opts.select { _2.dig(:meta, :was) == field }.keys.first

      unless was_name
        print "Remove column #{@table_name}.#{field} (y/N): ".colorize(:light_blue)
        if !Lux.env.production? && STDIN.gets.chomp.downcase.index('y')
          begin
            self.db.drop_column @table_name, field
            puts " drop_column #{field}".colorize(:green)
          rescue Sequel::DatabaseError => e
            raise unless e.message.include?('UndefinedColumn')
            puts " skip drop #{field} (already removed)".colorize(:yellow)
          end
        end
      end
    end

    # loop trough defined fields in schema
    for field, opts_in in @fields
      was_name = @opts.dig field, :meta, :was

      # site_id meta: { was: :org_id }
      if was_name && !@object[field.to_sym] && @object[was_name]
        rename was_name, field
        next
      end

      type = opts_in[0]
      opts = opts_in[1]

      db_type = get_db_column_type(field)

      # create missing columns
      unless @object[field.to_sym]
        if db_type == :jsonb
          transaction_do "ALTER TABLE #{@table_name} ADD COLUMN #{field} jsonb DEFAULT '{}' NOT NULL;"
        else
          self.db.add_column @table_name, field, db_type, opts

          if opts[:array]
            default = type == :string ? "ARRAY[]::character varying[]" : "ARRAY[]::#{db_type}[]"
            transaction_do "ALTER TABLE #{@table_name} ALTER COLUMN #{field} SET DEFAULT #{default};"
          end
        end

        puts " add_column #{field}, #{db_type}, #{opts.to_json}".colorize(:green)
      end

      if current = @object[field]
        # unhandled db schema changes will not happen
        # ---
        # field   - field name
        # current - current db_schema
        # type    - new proposed type in schema
        # opts    - new proposed types

        # if we have type set as array and in db it is not array, fix that
        if opts[:array]
          # covert to array unless is array
          if !current[:db_type].include?('[]')
            transaction_do %[
              alter table #{@table_name} alter #{field} drop default;
              alter table #{@table_name} alter #{field} type #{current[:db_type]}[] using array[#{field}];
              alter table #{@table_name} alter #{field} set default '{}';
            ]

            puts " Converted #{@table_name}.#{field} to array type".colorize(:green)
          elsif !current[:default]
            # force default for array to be present
            default = type == :string ? "ARRAY[]::character varying[]" : "ARRAY[]::integer[]"
            transaction_do %[alter table #{@table_name} alter #{field} set default #{default};]
          end
        end

        # if we have array but schema says no array
        if !opts[:array] && current[:db_type].include?('[]')
          m = current[:type] == :integer ? "#{field}[0]" : "array_to_string(#{field}, ',')"

          transaction_do %[
            alter table #{@table_name} alter #{field} drop default;
            alter table #{@table_name} alter #{field} type #{current[:db_type].sub('[]','')} using #{m};
          ]

          puts " Converted #{@table_name}.#{field}[] to non array type".colorize(:red)
        end

        # if varchar limit size has changed
        if type == :string && !opts[:array] && current[:max_length] != opts[:limit]
          transaction_do "ALTER TABLE #{@table_name} ALTER COLUMN #{field} TYPE varchar(#{opts[:limit]});"
          puts " #{field} limit, #{current[:max_length]}-> #{opts[:limit]}".colorize(:green)
        end

        # covert from varchar to text
        if type == :text && current[:max_length]
          transaction_do "ALTER TABLE #{@table_name} ALTER COLUMN #{field} SET DATA TYPE text"
          puts " #{field} limit from  #{current[:max_length]} to no limit (text type)".colorize(:green)
        end

        # null true or false
        if current[:allow_null] != opts[:null]
          if !opts[:null] && opts[:default]
            log_run "UPDATE #{@table_name} SET #{field}='#{opts[:default]}' where #{field} IS NULL"
          end

          to_run = " #{field} #{opts[:null] ? 'DROP' : 'SET'} NOT NULL"
          log_run "ALTER TABLE #{@table_name} ALTER COLUMN #{to_run}"
        end

        # covert string to date
        if current[:type] == :string && [:date, :datetime].include?(type)
          type = :timestamp if type == :datetime
          log_run "ALTER TABLE #{@table_name} ALTER COLUMN #{field} TYPE #{type.to_s.upcase} using #{field}::#{type};"
        end

        # field default changed
        if current[:default].to_s != opts[:default].to_s
          # skip for arrays
          next if opts[:array]
          next if current[:default].to_s.index('{}') and opts[:default] == []
          next if current[:default].to_s.start_with?("'#{opts[:default]}':")

          if opts[:default].to_s.blank?
            log_run "ALTER TABLE #{@table_name} ALTER COLUMN #{field} drop default"
          else
            # '2019-12-31 23:00:00'::timestamp without time zone",
            # 2019-12-31 23:00:00 UTC
            next if current[:db_type].include?('timestamp') && current[:default].to_s.include?(opts[:default].to_s.split(' ').first)

            log_run "ALTER TABLE #{@table_name} ALTER COLUMN #{field} SET DEFAULT '#{opts[:default]}'; update #{@table_name} set #{field}='#{opts[:default]}' where #{field} is null;"
          end
        end

        if opts[:index]
          db_rule :add_index, field
        end
      end
    end
  end

  def rename field_old, field_new
    log_run "ALTER TABLE #{@table_name} RENAME COLUMN #{field_old} TO #{field_new}"
    puts " * renamed #{@table_name}.#{field_old} to #{@table_name}.#{field_new}"
    puts ' * please run auto migration again'
  end

  def db_rule type, name = nil, opts = {}
    case type.to_sym
    when :timestamps
      opts[:null] ||= false
      @fields[:created_at] = [:timestamp, opts]
      @fields[:updated_at] = [:timestamp, opts]
      @fields[:creator_ref] = [:string, opts]
      @fields[:updater_ref] = [:string, opts]
    when :polymorphic
      @fields["#{name}_ref".to_sym]  = [:string, opts.merge(limit: 100, index: true)]
      @fields["#{name}_type".to_sym] = [:string, opts.merge(limit: 100, index: true)]
    when :table
      # table :orgs do |t|
      #   t.table :users do |t|
      #   end
      # end
      first  = @table_name.to_s.singularize
      second = name.to_s.singularize
      t = self.class.new '%s_%s' % [first, second.pluralize]
      t.string '%s_ref' % first,  null: false
      t.string '%s_ref' % second, null: false
      yield t
      t.fix_fields
      t.update
    when :add_index
      field = name
      type = db.schema(@table_name).to_h[field.to_sym][:db_type] rescue nil

      if type && !@db_indexes.include?(field.to_s)
        if type.index('[]')
          db.run %[CREATE INDEX if not exists #{@table_name}_#{field}_gin_index on "#{@table_name}" USING GIN ("#{field}");]
          puts " * added array GIN index on #{field}".colorize(:green)
        else
          db.add_index @table_name, field.to_sym, if_not_exists: true
          puts " * added index on #{field}".colorize(:green)
        end
      end
    when :foreign_key
      local_field = name.keys.first
      foreign_table, foreign_id = name.values.first
      constraint_name = "#{@table_name}_#{foreign_table}_fkey"

      if self.db.tables.include?(foreign_table) # table can be in different database
        exists = self.db.fetch("SELECT * FROM pg_catalog.pg_constraint where conname='#{constraint_name}' limit 1").to_a
        unless exists.first
          command = %{ALTER TABLE #{@table_name} ADD CONSTRAINT "#{constraint_name}" FOREIGN KEY ("#{local_field}") REFERENCES "#{foreign_table}"("#{foreign_id}") ON DELETE CASCADE}
          # ALTER TABLE "public"."sites" ADD CONSTRAINT "orgs_fkey" FOREIGN KEY ("org_id") REFERENCES "public"."orgs"("id") ON DELETE CASCADE;
          self.db.run(command) rescue nil
          puts " added foreign_key #{constraint_name} -> #{foreign_table}.#{foreign_id}"
        end
      end
    else
      puts " unknown special DB type: #{type.to_s.colorize(:red)} (in #{@table_name})"
    end
  end

  def method_missing type, *args
    name = args[0]
    opts = args[1] || {}

    if [:string, :integer, :text, :boolean, :datetime, :date, :geography, :timestamp, :bytea].index(type)
      @fields[name.to_sym] = [type, opts]
    elsif type == :jsonb
      opts[:default] = {}
      @fields[name.to_sym] = [:jsonb, opts]
    elsif [:decimal, :float].index(type)
      opts[:precision] ||= 8
      opts[:scale] ||= 2
      @fields[name.to_sym] = [:decimal, opts]
    else
      raise "Unknown DB field type: #{type.to_s.colorize(:red)} (in table: #{@table_name})"
    end
  end
end
