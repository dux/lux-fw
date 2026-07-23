require 'shellwords'
require 'uri'

module LuxDb
  module_function

  def db_name_from_url(url)
    URI.parse(url).path.sub('/', '')
  end

  def db_backup_file_location(name)
    folder = './tmp/db_dump'
    Dir.mkdir(folder) unless Dir.exist?(folder)
    '%s/%s.sql' % [folder, name]
  end

  # Use psql -tAc with a quoted SELECT so we don't depend on shell-piped
  # output parsing and never interpolate name into the SQL text. Casting
  # the bound parameter keeps libpq happy when datname is unset.
  def db_exists? name
    Lux.shell.exec('psql', '-d', 'postgres', '-tAc',
      "SELECT 1 FROM pg_database WHERE datname = '#{name.to_s.gsub("'", "''")}'") == '1'
  end

  def dev_check!
    if Lux.env.prod?
      puts 'Refused: destructive DB operations are not allowed in production'.colorize(:red)
      exit 1
    end
  end

  def load_migrate_file(file, external: false)
    info = 'auto_migrate: %s' % file

    if !File.exist?(file)
      if block_given?
        yield
      else
        info += ' (skipping)'
      end

      Lux.shell.info info
    elsif external
      Lux.shell.info info
      Lux.shell('bundle', 'exec', 'lux', 'e', file, env: { 'DB_MIGRATE' => 'false' })
    else
      Lux.shell.info info
      load file
    end
  end

  def each_configured_db
    Lux::Db.configured_names.each do |name|
      url = Lux::Db.url_for(name)
      yield name, url, db_name_from_url(url)
    end
  end

  def check_db(url, db_name)
    puts "dbname: #{db_name}"
    Lux.shell 'psql', url, '-c', "SELECT current_database() AS db, pg_size_pretty(pg_database_size(current_database())) AS size, (SELECT count(*) FROM information_schema.tables WHERE table_schema='public') AS public_tables, version() AS version"
  end

  def exec_sql(url, sql)
    Lux.shell 'psql', url, '-v', 'ON_ERROR_STOP=1', '-f', '-', stdin_data: sql
  end

  # Force-rebuild every <db>_test from the model schema: drop, create, then run
  # db:am against the _test sibling (DB_<NAME> override points it there). Schema
  # comes from the lux_schema model definitions, so test DBs always match the
  # code - no dependency on a migrated main DB.
  def migrate_test_dbs
    Lux::Db.configured_names.each do |name|
      url = Lux::Db.url_for(name)
      next unless url

      test_db  = db_name_from_url(url) + '_test'
      test_url = url.sub(/\/[^\/]+$/, "/#{test_db}")

      Lux.shell 'dropdb', '--if-exists', test_db
      Lux.shell 'createdb', test_db

      Lux.shell 'bundle', 'exec', 'lux', 'db:am',
        env: { "DB_#{name.to_s.upcase}" => test_url }

      puts "Test database '#{test_db}' rebuilt from schema".colorize(:green)
    end
  end

end

namespace :db do
  task :info do
    desc 'Show configured databases'
    proc do |_opts|
      Lux::Db.configured_names.each do |name|
        url = Lux::Db.url_for(name)
        db_name = LuxDb.db_name_from_url(url)
        exists = LuxDb.db_exists?(db_name)
        status = exists ? 'exists'.colorize(:green) : 'missing'.colorize(:red)
        puts '  :%-10s %s (%s)' % [name, db_name, status]
      end
    end
  end

  task :create do
    desc 'Create databases if missing'
    proc do |_opts|
      Lux::Db.configured_names.each do |name|
        db_name = LuxDb.db_name_from_url(Lux::Db.url_for(name))

        if LuxDb.db_exists?(db_name)
          puts "Database '#{db_name}' already exists, exiting".colorize(:yellow)
          exit 0
        end

        Lux.shell 'createdb', db_name
        puts "Database '#{db_name}' created".colorize(:green)
      end
    end
  end


  task :check do
    desc 'Print DB info: name, size, public table count, version'
    needs :env
    proc do |_opts|
      LuxDb.each_configured_db do |_name, url, db_name|
        LuxDb.check_db(url, db_name)
      end
    end
  end

  task :exec do
    desc 'Run a SQL statement via psql -f (stdin)'
    needs :env
    opt :sql, desc: 'SQL to execute (required; use - for stdin)'
    proc do |opts|
      sql = opts[:sql].to_s
      sql = $stdin.read if sql == '-'
      Lux.shell.die('--sql is required') if sql.strip.empty?

      LuxDb.each_configured_db do |_name, url, _db_name|
        LuxDb.exec_sql(url, sql)
      end
    end
  end

  task :psql do
    desc 'Run PSQL console'
    needs :env
    proc do |opts|
      name = (opts[:args].first || :main).to_sym
      url = Lux::Db.url_for(name)

      unless url
        puts "Database :#{name} not configured".colorize(:red)
        exit 1
      end

      system 'psql', url
    end
  end

  task :destroy do
    desc 'Drop databases (alias for db:drop)'
    needs :env
    proc { |_opts| hammer 'db:drop' }
  end

  task :drop do
    desc 'Drop databases (including test)'
    needs :env
    proc do |_opts|
      LuxDb.dev_check!

      Lux::Db.disconnect_all

      Lux::Db.configured_names.each do |name|
        db_name = LuxDb.db_name_from_url(Lux::Db.url_for(name))

        for db in [db_name + '_test', db_name]
          if LuxDb.db_exists?(db)
            Lux.shell 'dropdb', db
            puts "Database '#{db}' dropped".colorize(:green)
          else
            puts "Database '#{db}' does not exist, skipping".colorize(:yellow)
          end
        end
      end
    end
  end

  task :reset do
    desc 'Drop, create and auto migrate databases'
    needs :env
    proc do |_opts|
      LuxDb.dev_check!
      hammer 'db:drop'
      hammer 'db:create'
      hammer 'db:am'
    end
  end

  task :backup do
    desc 'Dump/backup databases to SQL'
    needs :env
    proc do |_opts|
      Lux::Db.configured_names.each do |name|
        url = Lux::Db.url_for(name)
        db_name = LuxDb.db_name_from_url(url)
        sql_file = LuxDb.db_backup_file_location(db_name)
        # shell mode needed for stdout redirect (>); interpolated values are
        # shellescaped to keep injection-prone characters from leaking through.
        Lux.shell "pg_dump --no-privileges --no-owner #{url.shellescape} > #{sql_file.shellescape}", shell: true
        puts "Backed up '#{db_name}' to #{sql_file}".colorize(:green)
        Lux.shell 'ls', '-lh', sql_file
      end
    end
  end

  task :restore do
    desc 'Restore databases from SQL backup'
    needs :env
    proc do |_opts|
      LuxDb.dev_check!

      Lux::Db.disconnect_all

      Lux::Db.configured_names.each do |name|
        url = Lux::Db.url_for(name)
        db_name = LuxDb.db_name_from_url(url)
        sql_file = LuxDb.db_backup_file_location(db_name)

        unless File.exist?(sql_file)
          puts "Backup not found: #{sql_file}".colorize(:red)
          next
        end

        Lux.shell 'dropdb', '--if-exists', db_name
        Lux.shell 'createdb', db_name
        # shell mode for stdin redirect (<); both values are shellescaped.
        Lux.shell 'psql -q %s < %s' % [db_name.shellescape, sql_file.shellescape], shell: true
        puts "Database '#{db_name}' restored from #{sql_file}".colorize(:green)
      end
    end
  end

  namespace :test do
    task :am do
      desc 'Force-rebuild test DBs (<db>_test) from the model schema'
      needs :env
      proc do |_opts|
        LuxDb.migrate_test_dbs
      end
    end

    task :drop do
      desc 'Drop test databases'
      needs :env
      proc do |_opts|
        Lux::Db.configured_names.each do |name|
          url = Lux::Db.url_for(name)
          test_db = LuxDb.db_name_from_url(url) + '_test'

          if LuxDb.db_exists?(test_db)
            Lux.shell 'dropdb', test_db
            puts "Test database '#{test_db}' dropped".colorize(:green)
          else
            puts "Test database '#{test_db}' does not exist".colorize(:yellow)
          end
        end
      end
    end
  end


  task :seed do
    desc 'Load seed from ./db/seeds and plugins/*/seeds'
    opt :full, type: :boolean, desc: 'Import all map seeds (default: first 50 per category)'
    opt :no_reset, type: :boolean, desc: 'Keep existing DB (skip db:reset); continue / re-seed'
    # needs :env (not :app) so models load inside db:am where DB_MIGRATE=true
    # creates their tables; loading models on an empty DB makes enum checks
    # against db_schema fail.
    needs :env
    proc do |opts|
      previous_seed_full = ENV['DB_SEED_FULL']
      ENV['DB_SEED_FULL'] = opts[:full] ? 'true' : nil

      begin
        LuxDb.dev_check!

        Lux::Db.disconnect_all

        hammer 'db:reset' unless opts[:no_reset]
        puts 'db:seed --no-reset (keeping existing data)'.colorize(:yellow) if opts[:no_reset]

        LuxDb.load_migrate_file './db/seed.rb' do
          for file in Dir['db/seeds/*.rb'].sort
            puts 'Seed: %s' % file.colorize(:green)
            load file
          end

          # Plugin-shipped seeds (plugin/seeds/*.rb only — not demo/).
          # Demo fixtures (e.g. fake lux_exceptions) live under plugin/demo/
          # and must be loaded explicitly. Skip re-running plugin seeds on
          # --no-reset so continue-seeds don't re-insert fixture data.
          unless opts[:no_reset]
            Lux::Plugin::PLUGIN.each_value do |plugin|
              files = Dir[::File.join(plugin.folder, 'seeds/*.rb')].sort
              next if files.empty?
              for file in files
                puts 'Seed (%s): %s' % [plugin.name, file.colorize(:green)]
                load file
              end
            end
          end
        end
      ensure
        ENV['DB_SEED_FULL'] = previous_seed_full
      end
    end
  end

  task :console do
    desc 'Run PSQL console'
    needs :env
    proc { |opts| hammer 'db:psql', *opts[:args] }
  end

  task :am do
    desc 'Automigrate schema (drops removed columns by default; --ask to confirm each)'
    needs :env
    opt :ask, type: :boolean, desc: 'Prompt before dropping columns (default: drop without asking)'
    proc do |opts|
      ENV['DB_MIGRATE'] = 'true' unless ENV['DB_MIGRATE'] == 'true'

      # AutoMigrate is auto-loaded by `Lux.plugin :db` (see plugins/db/migrate/auto_migrate.rb).
      # Column drops apply automatically; --ask restores the interactive y/N confirmation.
      AutoMigrate.auto_confirm = !opts[:ask]

      DB.run %[DROP TABLE IF EXISTS lux_tests;]
      DB.run %[CREATE TABLE lux_tests (int_array integer[] default '{}');]
      DB.run %[INSERT INTO lux_tests DEFAULT VALUES;]
      row = DB[:lux_tests].first
      Lux.shell.die('"DB.extension :pg_array" not loaded') unless row[:int_array].is_a?(Sequel::Postgres::PGArray)
      DB.run %[DROP TABLE IF EXISTS lux_tests;]

      LuxDb.load_migrate_file './db/before.rb'
      LuxDb.load_migrate_file './db/auto_migrate.rb'

      # re-apply schemas for models loaded before AutoMigrate was defined (e.g. plugin models)
      Lux.schema(type: :model).each do |klass_name|
        AutoMigrate.apply_schema klass_name
      end

      LuxDb.load_migrate_file './db/after.rb', external: true
    end
  end
end
