def db_backup_file_location args
  folder = './tmp/db_dump'
  Dir.mkdir(folder) unless Dir.exist?(folder)
  name = args[:name] || Lux.config.db_url.split('/').last
  "%s/%s.sql" % [folder, name]
end

db_name = Lux.config(:db_url).split('/').last

###

namespace :db do
  desc 'Reset database (drop, create, auto migrate, seed)'
  task :reset do
    invoke  'db:drop'
    invoke  'db:create'
    invoke  'db:am'
    Lux.run 'rake db:am'

    reset_db = 'db/backups/reset.sql'
    FileUtils.mkdir_p('db/backups')

    Lux.run "pg_dump --no-privileges --no-owner --no-reconnect #{db_name} > '#{reset_db}'"
    Lux.run "psql #{db_name}_test < #{reset_db}"
  end

  desc 'Create database'
  task :create do
    Lux.run "createdb #{db_name}"
    Lux.run "createdb #{db_name}_test"
  end

  desc 'Drop database'
  task :drop do
    DB.disconnect
    Lux.run "dropdb #{db_name}"
    Lux.run "dropdb #{db_name}_test"
  end

  desc 'Run PSQL console'
  task :console do
    system "psql '%s'" % Lux.config(:db_url)
  end

  desc 'Automigrate schema'
  task :am do
    class Object
      def self.const_missing klass, path=nil
        eval 'class ::%s; end' % klass
        Object.const_get(klass)
      end
    end

    Lux.config.migrate = true

    load Lux.fw_root.join('plugins/db/auto_migrate/auto_migrate.rb').to_s

    # Sequel extension and plugin test
    DB.run %[DROP TABLE IF EXISTS lux_tests;]
    DB.run %[CREATE TABLE lux_tests (int_array integer[] default '{}', text_array text[] default '{}');]
    class LuxTest < Sequel::Model; end;
    LuxTest.new.save
    die('"DB.extension :pg_array" not loaded') unless LuxTest.first.int_array.class == Sequel::Postgres::PGArray
    DB.run %[DROP TABLE IF EXISTS lux_tests;]

    require './db/schema'

    for klass in Typero.list
      AutoMigrate.typero klass
    end
  end

  desc 'Dump database backup'
  task :dump, [:name] => :env do |_, args|
    sql_file = db_backup_file_location args

    Lux.run "pg_dump --no-privileges --no-owner --no-reconnect #{Lux.config(:db_url)} > #{sql_file}"
    system 'ls -lh %s' % sql_file
  end

  desc 'Restore database backup'
  task :restore, [:name] => :env do |_, args|
    sql_file = db_backup_file_location args

    invoke 'db:drop'
    invoke 'db:create'
    Lux.run 'psql %s < %s' % [db_name, sql_file]
  end
end
