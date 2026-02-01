# https://sequel.jeremyevans.net/rdoc/classes/Sequel/Database.html

# auto migrate database tables, create tables and fileds, drop if needed
# idea is that cols and actions are executedm only if needed

# db = Sequel.sqlite

# SequelTable db, :customers do
#   col :name, String
#   col :foo, String
#   col :email, type(:email)
# end

# SequelTable.rename_table DB, :customers, :customers2

# SequelTable db, :customers2 do
#   drop :foo
#   col :name_foo, String
#   rename :name, :name2
# end

###

def SequelTable db, table, &block
  st = SequelTable.new db, table
  st.instance_exec self, &block
  st.summary
end

class SequelTable
  class << self
    # rename table if source exist
    def rename_table db, old_name, new_name
      if db.table_exists?(old_name)
        db.rename_table old_name, new_name
        $stdout.puts "* SequelTable in #{db.opts[:database]} rename #{old_name} to #{new_name}"
      end
    end
  end

  ###

  def initialize db, table
    @db = db
    @table_name = table
    @used_fileds = []

    db.create_table? table do
      primary_key :id
    end
  end

  # reloads table schema for classes
  def reload_schema
    @table_name.to_s.classify.constantize.set_dataset(@table_name)
  end

  # creates filed unless exists
  def col field, type, opts = {}
    @used_fileds.push field

    if type.is?(Typero::Type)
      type, db_opts = type.new(nil).db_field
      opts.merge! db_opts
    end

    type = :string if type == String
    type = :integer if type == Integer

    validate_options field, opts
    unless schema_for(field)
      @db.add_column @table_name, field, type, opts
      info "DB migrate: Adding field #{field} (#{type})"
    end
  end

  # drops field, if one exists
  def drop field
    @used_fileds.push field

    if schema_for(field)
      @db.drop_column @table_name, field
      info "DB migrate: Dropping field #{field}"
    end
  end

  # renames field, if new filed does not exist
  def rename filed_from, filed_to
    @used_fileds.push filed_to

    if schema_for(filed_from)
      @db.rename_column @table_name, filed_from, filed_to
      info "DB migrate: Renamed filed from #{filed_from} to #{filed_to}"
    end
  end

  def type name
    Typero.type name
  end

  def summary
    unused = @table_schema.keys - [:id] - @used_fileds

    if unused.first
      info "Unused fileds present in DB -> #{unused.join(', ')}"
    end

    @used_fileds
  end

  def info text
    $stdout.puts "* SequelTable #{@db.opts[:database]}[#{@table_name}]: #{text}"
  end

  def schema_for name, reload: false
    if !@table_schema || reload
      @table_schema = @db.schema(@table_name, reload: true).to_h rescue {}
    end
    
    @table_schema[name]
  end

  # raise if invalid options are found
  def validate_options field, opts = {}
    valid = [:default, :null, :index, :unique, :check, :foreign_key, :array, :size]
    invalid = opts.keys - valid
    raise %{Invalid option "#{invalid.join(', ')}" in table #{@table_name}[#{field}]} if invalid.first
  end
end

