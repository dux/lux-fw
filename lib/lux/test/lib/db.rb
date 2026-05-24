module Lux
  module Test
    # with_transaction { ... } wraps the block in a Sequel transaction and
    # rolls back at the end. The constant DB must be set to a Sequel connection
    # before this is used (db-touching specs assign DB themselves).
    module DB
      def with_transaction
        raise 'with_transaction needs a top-level DB Sequel connection' unless defined?(::DB) && ::DB.respond_to?(:transaction)

        ::DB.transaction(rollback: :always) { yield }
      end

      # Hard-truncate the given tables; useful when a spec cannot run inside a
      # transaction (e.g. tests that themselves open transactions or use
      # LISTEN/NOTIFY which doesn't fire until commit).
      def truncate *tables
        raise 'truncate needs a top-level DB Sequel connection' unless defined?(::DB)

        tables.each { |t| ::DB.run('TRUNCATE TABLE %s RESTART IDENTITY CASCADE' % t) }
      end
    end
  end
end
