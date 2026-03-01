# When DB_MIGRATE is set (rake db:am), auto-create missing tables
# so that Sequel model classes can load without PG::UndefinedTable errors.
# AutoMigrate will add the real columns afterwards.

if ENV['DB_MIGRATE']
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
end
