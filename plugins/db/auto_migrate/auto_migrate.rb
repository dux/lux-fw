# https://github.com/jeremyevans/sequel/blob/master/doc/schema_modification.rdoc
#
# Auto-migrates database schema based on Typero model definitions.
# Triggered by Typero sequel adapter when ENV['DB_MIGRATE'] == 'true'.
#
# Usage: rake db:am (sets DB_MIGRATE=true before loading models)

class AutoMigrate
  SIMPLE_TYPES  = %i[string integer text boolean datetime date geography timestamp bytea].freeze
  DECIMAL_TYPES = %i[decimal float].freeze

  attr_accessor :fields

  class << self
    attr_accessor :auto_confirm

    def apply_schema klass
      @applied ||= Set.new
      klass = klass.constantize if klass.is_a?(String)
      return if @applied.include?(klass)
      @applied << klass

      schema = Typero.schema(klass)

      am = new(klass.db)
      am.table klass, schema.rules do |f|
        schema.db_schema.each do |field, type, opts|
          f.send type, field, opts
        end

        schema.db_rules.each do |args|
          f.db_rule *args
        end
      end

      klass.db.schema(klass.to_s.tableize, reload: true)
      klass.set_dataset(klass.to_s.tableize.to_sym)
      klass
    end
  end

  ###

  def initialize db_connection = nil
    @db = db_connection
  end

  def db
    @db || DB
  end

  # Create table if missing, load current DB state, apply schema block
  def table table_name, opts = {}
    @fields       = {}
    @table_name   = table_name.to_s.tableize.to_sym
    @field_opts   = opts || {}

    create_table_if_missing
    load_current_state

    if block_given?
      yield self
      normalize_fields
      sync_schema
    end
  end

  # Expand DSL directives (timestamps, polymorphic, etc.) into concrete fields/indexes
  def db_rule type, name = nil, opts = {}
    # puts ">>> db_rule #{type} - #{name}"

    case type.to_sym
    when :timestamps
      opts[:null] ||= false
      @fields[:created_at]  = [:timestamp, opts]
      @fields[:updated_at]  = [:timestamp, opts]
      @fields[:creator_ref] = [:string, opts]
      @fields[:updater_ref] = [:string, opts]
    when :polymorphic
      @fields["#{name}_ref".to_sym]  = [:string, opts.merge(limit: 100, index: true)]
      @fields["#{name}_type".to_sym] = [:string, opts.merge(limit: 100, index: true)]
    when :table
      create_join_table(name) { |t| yield t if block_given? }
    when :add_index
      add_index_for name
    when :foreign_key
      add_foreign_key name
    else
      puts " unknown db_rule type: #{type.to_s.colorize(:red)} (in #{@table_name})"
    end
  end

  def enable_extension name
    db.run "CREATE EXTENSION IF NOT EXISTS #{name};"
  end

  def extension name
    exists = db["SELECT extname FROM pg_extension where extname='#{name}'"].to_a.first
    run_sql "CREATE EXTENSION #{name}" unless exists
  end

  def rename field_old, field_new
    run_sql "ALTER TABLE #{@table_name} RENAME COLUMN #{field_old} TO #{field_new}"
    puts " * renamed #{@table_name}.#{field_old} to #{@table_name}.#{field_new}"
    puts ' * please run auto migration again'
  end

  # Register a column via method_missing: f.string :name, limit: 100
  def method_missing type, *args
    name = args[0]
    opts = args[1] || {}

    if SIMPLE_TYPES.include?(type)
      @fields[name.to_sym] = [type, opts]
    elsif type == :jsonb
      @fields[name.to_sym] = [:jsonb, opts.merge(default: {})]
    elsif DECIMAL_TYPES.include?(type)
      opts[:precision] ||= 8
      opts[:scale]     ||= 2
      @fields[name.to_sym] = [:decimal, opts]
    else
      raise "Unknown DB field type: #{type.to_s.colorize(:red)} (in table: #{@table_name})"
    end
  end

  private

  # --- setup ---

  def create_table_if_missing
    return if db.table_exists?(@table_name.to_s)

    db.create_table(@table_name) do
      String :ref, primary_key: true
    end
  end

  def load_current_state
    @current_schema = db.schema(@table_name).to_h

    @db_indexes = db
      .fetch("SELECT indexname FROM pg_indexes WHERE tablename = '#{@table_name}';")
      .to_a
      .map { _1[:indexname] }
      .reject { _1.end_with?('_pkey') }
      .map { _1.sub(/_index$/, '').sub("#{@table_name}_", '') }
  end

  # --- field normalization ---

  def normalize_fields
    @fields.each_value do |type, opts|
      opts[:limit]   ||= 255   if type == :string
      opts[:default] ||= false if type == :boolean
      opts[:null]      = true  unless opts[:null] == false
      opts[:array]   ||= false
      opts[:unique]  ||= false
      opts[:default]   = []    if opts[:array]
    end
  end

  def db_column_type field
    type, opts = @fields[field]

    db_type = case type
              when :string    then "varchar(#{opts[:limit] || 255})"
              when :timestamp then :timestamp
              else type
              end

    opts[:array] ? "#{db_type}[]" : db_type
  end

  # --- schema sync ---

  def sync_schema
    puts "Table #{@table_name.to_s.colorize(:yellow)}, #{@fields.length} fields in #{db.uri.split('/').last}"

    remove_extra_columns
    sync_columns
  end

  def remove_extra_columns
    extra = @current_schema.keys - @fields.keys - [:id, :ref]

    extra.each do |field|
      # skip if another field declares meta: { was: :this_field } — will be renamed
      next if @field_opts.any? { |_, v| v.dig(:meta, :was) == field }

      if AutoMigrate.auto_confirm
        puts "Remove column #{@table_name}.#{field} (auto-confirmed)".colorize(:light_blue)
      else
        print "Remove column #{@table_name}.#{field} (y/N): ".colorize(:light_blue)
        next if Lux.env.production? || !STDIN.gets.chomp.downcase.index('y')
      end

      begin
        db.drop_column @table_name, field
        puts " drop_column #{field}".colorize(:green)
      rescue Sequel::DatabaseError => e
        raise unless e.message.include?('UndefinedColumn')
        puts " skip drop #{field} (already removed)".colorize(:yellow)
      end
    end
  end

  def sync_columns
    @fields.each do |field, (type, opts)|
      # handle column rename via meta: { was: :old_name }
      was_name = @field_opts.dig(field, :meta, :was)
      if was_name && !@current_schema[field.to_sym] && @current_schema[was_name]
        rename was_name, field
        next
      end

      db_type = db_column_type(field)
      current = @current_schema[field]

      if current
        alter_column field, type, opts, current, db_type
      else
        create_column field, type, opts, db_type
      end
    end
  end

  # --- column creation ---

  def create_column field, type, opts, db_type
    if db_type == :jsonb
      transaction_do "ALTER TABLE #{@table_name} ADD COLUMN #{field} jsonb DEFAULT '{}' NOT NULL;"
    else
      db.add_column @table_name, field, db_type, opts

      if opts[:array]
        default = type == :string ? "ARRAY[]::character varying[]" : "ARRAY[]::#{db_type}[]"
        transaction_do "ALTER TABLE #{@table_name} ALTER COLUMN #{field} SET DEFAULT #{default};"
      end
    end

    puts " add_column #{field}, #{db_type}, #{opts.to_json}".colorize(:green)
  end

  # --- column alteration ---

  def alter_column field, type, opts, current, db_type
    alter_array_type field, type, opts, current
    alter_varchar_limit field, type, opts, current
    alter_text_conversion field, type, current
    alter_null_constraint field, opts, current
    alter_string_to_date field, type, current
    alter_default field, type, opts, current
    db_rule(:add_index, field) if opts[:index]
  end

  # Convert between scalar <-> array column types
  def alter_array_type field, type, opts, current
    if opts[:array] && !current[:db_type].include?('[]')
      # scalar → array
      transaction_do %[
        alter table #{@table_name} alter #{field} drop default;
        alter table #{@table_name} alter #{field} type #{current[:db_type]}[] using array[#{field}];
        alter table #{@table_name} alter #{field} set default '{}';
      ]
      puts " Converted #{@table_name}.#{field} to array type".colorize(:green)
    elsif opts[:array] && !current[:default]
      # array column missing default
      default = type == :string ? "ARRAY[]::character varying[]" : "ARRAY[]::integer[]"
      transaction_do "alter table #{@table_name} alter #{field} set default #{default};"
    elsif !opts[:array] && current[:db_type].include?('[]')
      # array → scalar
      cast = current[:type] == :integer ? "#{field}[0]" : "array_to_string(#{field}, ',')"
      transaction_do %[
        alter table #{@table_name} alter #{field} drop default;
        alter table #{@table_name} alter #{field} type #{current[:db_type].sub('[]', '')} using #{cast};
      ]
      puts " Converted #{@table_name}.#{field}[] to non array type".colorize(:red)
    end
  end

  def alter_varchar_limit field, type, opts, current
    return unless type == :string && !opts[:array] && current[:max_length] != opts[:limit]

    transaction_do "ALTER TABLE #{@table_name} ALTER COLUMN #{field} TYPE varchar(#{opts[:limit]});"
    puts " #{field} limit, #{current[:max_length]}-> #{opts[:limit]}".colorize(:green)
  end

  def alter_text_conversion field, type, current
    return unless type == :text && current[:max_length]

    transaction_do "ALTER TABLE #{@table_name} ALTER COLUMN #{field} SET DATA TYPE text"
    puts " #{field} limit from  #{current[:max_length]} to no limit (text type)".colorize(:green)
  end

  def alter_null_constraint field, opts, current
    return if current[:allow_null] == opts[:null]

    if !opts[:null] && opts[:default]
      run_sql "UPDATE #{@table_name} SET #{field}='#{opts[:default]}' where #{field} IS NULL"
    end

    action = opts[:null] ? 'DROP' : 'SET'
    run_sql "ALTER TABLE #{@table_name} ALTER COLUMN #{field} #{action} NOT NULL"
  end

  def alter_string_to_date field, type, current
    return unless current[:type] == :string && [:date, :datetime].include?(type)

    pg_type = type == :datetime ? :timestamp : type
    run_sql "ALTER TABLE #{@table_name} ALTER COLUMN #{field} TYPE #{pg_type.to_s.upcase} using #{field}::#{pg_type};"
  end

  def alter_default field, type, opts, current
    return if current[:default].to_s == opts[:default].to_s
    return if opts[:array]
    return if current[:default].to_s.index('{}') && opts[:default] == []
    return if current[:default].to_s.start_with?("'#{opts[:default]}':")

    if opts[:default].to_s.blank?
      run_sql "ALTER TABLE #{@table_name} ALTER COLUMN #{field} drop default"
    else
      # skip timestamp defaults that already match: '2019-12-31 23:00:00'::timestamp...
      return if current[:db_type].include?('timestamp') &&
                current[:default].to_s.include?(opts[:default].to_s.split(' ').first)

      run_sql "ALTER TABLE #{@table_name} ALTER COLUMN #{field} SET DEFAULT '#{opts[:default]}'; update #{@table_name} set #{field}='#{opts[:default]}' where #{field} is null;"
    end
  end

  # --- db_rule helpers ---

  def create_join_table name
    first  = @table_name.to_s.singularize
    second = name.to_s.singularize

    join = self.class.new(db)
    join.table "#{first}_#{second.pluralize}" do |t|
      t.string "#{first}_ref",  null: false
      t.string "#{second}_ref", null: false
      yield t if block_given?
    end
  end

  def add_index_for field
    col_type = db.schema(@table_name).to_h[field.to_sym][:db_type] rescue nil
    return unless col_type && !@db_indexes.include?(field.to_s)

    if col_type.include?('[]')
      db.run %[CREATE INDEX if not exists #{@table_name}_#{field}_gin_index on "#{@table_name}" USING GIN ("#{field}");]
      puts " * added array GIN index on #{field}".colorize(:green)
    else
      db.add_index @table_name, field.to_sym, if_not_exists: true
      puts " * added index on #{field}".colorize(:green)
    end
  end

  def add_foreign_key name
    local_field = name.keys.first
    foreign_table, foreign_id = name.values.first
    constraint_name = "#{@table_name}_#{foreign_table}_fkey"

    return unless db.tables.include?(foreign_table)

    exists = db.fetch("SELECT 1 FROM pg_catalog.pg_constraint where conname='#{constraint_name}' limit 1").to_a
    return if exists.first

    sql = %{ALTER TABLE #{@table_name} ADD CONSTRAINT "#{constraint_name}" FOREIGN KEY ("#{local_field}") REFERENCES "#{foreign_table}"("#{foreign_id}") ON DELETE CASCADE}
    db.run(sql) rescue nil
    puts " added foreign_key #{constraint_name} -> #{foreign_table}.#{foreign_id}"
  end

  # --- sql helpers ---

  def run_sql sql
    puts " #{sql}".colorize(:green)
    transaction_do sql
  end

  def transaction_do sql
    db.run "BEGIN; #{sql} ;COMMIT;"
  rescue
    puts caller[1].colorize(:red)
    puts sql.colorize(:yellow)
    raise
  end
end
