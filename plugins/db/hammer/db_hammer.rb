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

      Lux.info info
    elsif external
      Lux.info info
      Lux.run "DB_MIGRATE=false bundle exec lux e #{file}"
    else
      Lux.info info
      load file
    end
  end
end

namespace :db do
  task :info do
    desc 'Show configured databases'
    needs :env
    proc do |_opts|
      Lux::Db.configured_names.each do |name|
        url = Lux::Db.url_for(name)
        db_name = LuxDb.db_name_from_url(url)
        exists = system("psql -lqt | cut -d \\| -f 1 | grep -qw #{db_name}")
        status = exists ? 'exists'.colorize(:green) : 'missing'.colorize(:red)
        puts '  :%-10s %s (%s)' % [name, db_name, status]
      end
    end
  end

  task :create do
    desc 'Create databases if missing'
    needs :env
    proc do |_opts|
      Lux::Db.configured_names.each do |name|
        db_name = LuxDb.db_name_from_url(Lux::Db.url_for(name))

        if system("psql -lqt | cut -d \\| -f 1 | grep -qw #{db_name}")
          puts "Database '#{db_name}' already exists".colorize(:yellow)
        else
          Lux.run 'createdb %s' % db_name
          puts "Database '#{db_name}' created".colorize(:green)
        end
      end
    end
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
          if system("psql -lqt | cut -d \\| -f 1 | grep -qw #{db}")
            system 'dropdb %s' % db
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
        Lux.run "pg_dump --no-privileges --no-owner '#{url}' > #{sql_file}"
        puts "Backed up '#{db_name}' to #{sql_file}".colorize(:green)
        system 'ls -lh %s' % sql_file
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

        system 'dropdb --if-exists %s' % db_name
        system 'createdb %s' % db_name
        Lux.run 'psql -q %s < %s' % [db_name, sql_file]
        puts "Database '#{db_name}' restored from #{sql_file}".colorize(:green)
      end
    end
  end

  namespace :test do
    task :create do
      desc 'Recreate test DBs (drop if exists, copy schema from main, run db:am if main missing)'
      needs :env
      proc do |_opts|
        Lux::Db.configured_names.each do |name|
          url = Lux::Db.url_for(name)
          source_db = LuxDb.db_name_from_url(url)
          test_db = source_db + '_test'

          if system("psql -lqt | cut -d \\| -f 1 | grep -qw #{test_db}")
            system 'dropdb %s' % test_db
            puts "Test database '#{test_db}' dropped".colorize(:yellow)
          end

          unless system("psql -lqt | cut -d \\| -f 1 | grep -qw #{source_db}")
            puts "Main database '#{source_db}' missing, creating and running db:am".colorize(:yellow)
            system 'createdb %s' % source_db
            hammer 'db:am'
          end

          system 'createdb %s' % test_db
          system 'pg_dump --schema-only --no-owner --no-privileges %s | psql -q %s > /dev/null 2>&1' % [source_db, test_db]
          puts "Test database '#{test_db}' created (schema from #{source_db})".colorize(:green)
        end
      end
    end

    task :drop do
      desc 'Drop test databases'
      needs :env
      proc do |_opts|
        Lux::Db.configured_names.each do |name|
          url = Lux::Db.url_for(name)
          test_db = LuxDb.db_name_from_url(url) + '_test'

          if system("psql -lqt | cut -d \\| -f 1 | grep -qw #{test_db}")
            system 'dropdb %s' % test_db
            puts "Test database '#{test_db}' dropped".colorize(:green)
          else
            puts "Test database '#{test_db}' does not exist".colorize(:yellow)
          end
        end
      end
    end
  end

  task :seed do
    desc 'Load seed from ./db/seeds'
    needs :app
    proc do |_opts|
      LuxDb.dev_check!

      Lux::Db.disconnect_all

      hammer 'db:reset'

      LuxDb.load_migrate_file './db/seed.rb' do
        for file in Dir['db/seeds/*.rb'].sort
          puts 'Seed: %s' % file.colorize(:green)
          load file
        end
      end
    end
  end

  task :gen_seeds do
    desc 'Generate seeds'
    needs :app
    proc do |opts|
      klass_name, ref = opts[:args]
      Lux.die 'argument not given => lux db:gen_seeds [model]' unless klass_name

      klass = klass_name.classify.constantize
      data = klass.xwhere(ref: ref).limit(100).all.map(&:seed).join("\n\n")

      puts data
    end
  end

  task :console do
    desc 'Run PSQL console'
    needs :env
    proc do |opts|
      name = (opts[:args].first || :main).to_sym
      url = Lux::Db.url_for(name)

      unless url
        puts "Database :#{name} not configured".colorize(:red)
        exit 1
      end

      system "psql '%s'" % url
    end
  end

  task :am do
    desc 'Automigrate schema (pass y to auto-confirm column drops: db:am y)'
    needs :env
    proc do |opts|
      ENV['DB_MIGRATE'] = 'true' unless ENV['DB_MIGRATE'] == 'true'

      # AutoMigrate is auto-loaded by `Lux.plugin :db` (see plugins/db/load/auto_migrate.rb).
      AutoMigrate.auto_confirm = opts[:args].first == 'y'

      DB.run %[DROP TABLE IF EXISTS lux_tests;]
      DB.run %[CREATE TABLE lux_tests (int_array integer[] default '{}');]
      DB.run %[INSERT INTO lux_tests DEFAULT VALUES;]
      row = DB[:lux_tests].first
      Lux.die('"DB.extension :pg_array" not loaded') unless row[:int_array].is_a?(Sequel::Postgres::PGArray)
      DB.run %[DROP TABLE IF EXISTS lux_tests;]

      LuxDb.load_migrate_file './db/before.rb'
      LuxDb.load_migrate_file './db/auto_migrate.rb'

      # re-apply schemas for models loaded before AutoMigrate was defined (e.g. plugin models)
      Typero.schema(type: :model).each do |klass_name|
        AutoMigrate.apply_schema klass_name
      end

      LuxDb.load_migrate_file './db/after.rb', external: true
    end
  end
end
