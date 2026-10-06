# A model whose table does not exist yet gets a bare `ref` table on class load,
# so AutoMigrate can then add its columns. Only db:am (and a boot with
# DB_MIGRATE=true) installs this - any other command must fail loudly on a
# missing table instead of creating one.
Sequel::Model.class_eval do
  class << self
    alias_method :_set_dataset_original, :set_dataset

    def set_dataset(*args, &block)
      _set_dataset_original(*args, &block)
    rescue Sequel::DatabaseError => e
      raise unless e.wrapped_exception.is_a?(PG::UndefinedTable)
      table_name = args.first.is_a?(Symbol) ? args.first : implicit_table_name
      db.create_table(table_name) do
        String :ref, primary_key: true
      end
      _set_dataset_original(*args, &block)
    end
  end
end
