# https://github.com/jeremyevans/sequel/blob/master/doc/schema_modification.rdoc

class AutoMigrate
  attr_accessor :fields

  class << self
    def table table_name, opts={}
      die "Table [#{table_name}] not in plural -> expected [#{table_name.to_s.pluralize}]" unless table_name.to_s.pluralize == table_name.to_s

      die 'Table name "%s" is not permited' % table_name if [:categories].include?(table_name)

      unless DB.table_exists?(table_name.to_s)
        # http://sequel.jeremyevans.net/rdoc/files/doc/schema_modification_rdoc.html
        DB.create_table table_name do
          primary_key :id, Integer
          index :id, unique: true
        end
      end

      t = new table_name, opts
      yield t
      t.fix_fields
      t.update
    end

    def migrate &block
      instance_eval &block
    end

    def enable_extension name
      DB.run 'CREATE EXTENSION IF NOT EXISTS %s;' % name
    end

    def transaction_do text
      begin
        DB.run 'BEGIN; %s ;COMMIT;' % text
      rescue
        puts caller[1].red
        puts text.yellow
        raise $!
      end
    end

  end

  ###

  def initialize table_name, opts={}
    @fields     = {}
    @opts       = opts
    @table_name = table_name

    klass = @table_name.to_s.classify

    Object.send(:remove_const, klass) if Object.const_defined?(klass)

    eval %[class ::%s < Sequel::Model; end;] % klass
    @object = klass.constantize.new
  end

  def transaction_do text
    self.class.transaction_do text
  end

  def log_run what
    puts ' %s' % what.green
    self.class.transaction_do what
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
    db_type = :varchar if type == :string
    db_type = Time if type == :datetime

    if opts[:array]
      db_type = '%s(%s)' % [db_type, opts[:limit]] if type == :string
      db_type = '%s[]' % db_type
    else
      db_type = 'varchar(%s)' % opts[:limit] if opts[:limit]
    end

    db_type
  end

  def update
    puts "Table #{@table_name.to_s.yellow}, #{@fields.keys.length} fields"

    # remove extra fields
    if @opts[:drop].class != FalseClass
      for field in (@object.columns - @fields.keys - [:id])
        print "Remove colum #{@table_name}.#{field} (y/N): ".light_blue
        if STDIN.gets.chomp.downcase.index('y')
          DB.drop_column @table_name, field
          puts " drop_column #{field}".green
        end
      end
    end

    # loop trough defined fileds in schema
    for field, opts_in in @fields
      type = opts_in[0]
      opts = opts_in[1]

      db_type = get_db_column_type(field)

      # create missing columns
      unless @object.columns.index(field.to_sym)
        DB.add_column @table_name, field, db_type, opts

        if opts[:array]
          default = type == :string ? "ARRAY[]::character varying[]" : "ARRAY[]::integer[]"
          transaction_do "ALTER TABLE #{@table_name} ALTER COLUMN #{field} SET DEFAULT #{default};"
        end

        puts " add_column #{field}, #{db_type}, #{opts.to_json}".green
        next
      end

      if current = @object.db_schema[field]
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

            puts " Coverted #{@table_name}.#{field} to array type".green
          elsif !current[:default]
            # force default for array to be present
            default = type == :string ? "ARRAY[]::character varying[]" : "ARRAY[]::integer[]"
            transaction_do %[alter table #{@table_name} alter #{field} set default #{default};]
          end
        end

        # if we have array but scema says no array
        if !opts[:array] && current[:db_type].include?('[]')
          m = current[:type] == :integer ? "#{field}[0]" : "array_to_string(#{field}, ',')"

          transaction_do %[
            alter table #{@table_name} alter #{field} drop default;
            alter table #{@table_name} alter #{field} type #{current[:db_type].sub('[]','')} using #{m};
          ]

          puts " Coverted #{@table_name}.#{field}[] to non array type".red
        end

        # if varchar limit size has changed
        if type == :string && !opts[:array] && current[:max_length] != opts[:limit]
          transaction_do "ALTER TABLE #{@table_name} ALTER COLUMN #{field} TYPE varchar(#{opts[:limit]});"
          puts " #{field} limit, #{current[:max_length]}-> #{opts[:limit]}".green
        end

        # covert from varchar to text
        if type == :text && current[:max_length]
          transaction_do "ALTER TABLE #{@table_name} ALTER COLUMN #{field} SET DATA TYPE text"
          puts " #{field} limit from  #{current[:max_length]} to no limit (text type)".green
        end

        # null true or false
        if current[:allow_null] != opts[:null]
          to_run = " #{field} #{opts[:null] ? 'DROP' : 'SET'} NOT NULL"
          log_run "ALTER TABLE #{@table_name} ALTER COLUMN #{to_run}"
        end

        # covert string to date
        if current[:type] == :string && [:date, :datetime].include?(type)
          log_run "ALTER TABLE #{@table_name} ALTER COLUMN #{field} TYPE #{type.to_s.upcase} using #{field}::#{type};"
        end

        #ap [current, field, type, opts] if current[:type] == :string && @table_name == :informators

        # field default changed
        if current[:default].to_s != opts[:default].to_s
          # skip for arrays
          next if opts[:array]
          next if current[:default].to_s.index('{}') and opts[:default] == []
          next if current[:default].to_s.starts_with?("'#{opts[:default]}':")

          if opts[:default].to_s.blank?
            log_run "ALTER TABLE #{@table_name} ALTER COLUMN #{field} drop default"
          else
            log_run "ALTER TABLE #{@table_name} ALTER COLUMN #{field} SET DEFAULT '#{opts[:default]}'; update #{@table_name} set #{field}='#{opts[:default]}' where #{field} is null;"
          end
        end

        if opts[:index]
          add_index(field)
        end
      end
    end

  end

  def add_index field
    type = @table_name.to_s.classify.constantize.new.db_schema[field][:db_type] rescue nil

    begin
      if type.index('[]')
        DB.run %[CREATE INDEX #{@table_name}_#{field}_gin_index on "#{@table_name}" USING GIN ("#{field}");]
        puts " * added array GIN index on #{field}".green
      else
        DB.add_index(@table_name, field)
        puts " * added index on #{field}".green
      end
    rescue; end
  end

  def rename field_old, field_new
    existing_fields = @table_name.to_s.classify.constantize.new.columns

    if existing_fields.index(field_old.to_sym) && ! existing_fields.index(field_new.to_sym)
      DB.rename_column(@table_name, field_old, field_new)
      puts " * renamed #{@table_name}.#{field_old} to #{@table_name}.#{field_new}"
      puts ' * please run auto migration again'
      exit
    end
  end

  def method_missing type, *args
    name = args[0]
    opts = args[1] || {}

    if [:string, :integer, :text, :boolean, :datetime, :date, :jsonb, :geography].index(type)
      @fields[name.to_sym] = [type, opts]
    elsif type == :decimal
      opts[:precision] ||= 8
      opts[:scale] ||= 2
      @fields[name.to_sym] = [:decimal, opts]
    elsif type == :timestamps
      opts[:null] ||= false
      @fields[:created_at] = [:datetime, opts]
      @fields[:created_by] = [:integer, opts]
      @fields[:updated_at] = [:datetime, opts]
      @fields[:updated_by] = [:integer, opts]
    elsif type == :polymorphic
      name ||= :model
      @fields["#{name}_id".to_sym]   = [:integer, opts.merge(index: true) ]
      @fields["#{name}_type".to_sym] = [:string, opts.merge(limit: 100, index: "#{name}_id")]
    else
      puts "Unknown #{type.to_s.red}"
    end
  end
end
