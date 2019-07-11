def db_backup_file_location args
  folder = './tmp/db_dump'
  Dir.mkdir(folder) unless Dir.exist?(folder)
  name = args[:name] || Lux.config.db_url.split('/').last
  "%s/%s.sql" % [folder, name]
end

namespace :db do
  desc 'Create database'
  task create: :env do
    db_name = Lux.config(:db_url).split('/').last
    Lux.run "createdb #{db_name}"
  end

  desc 'Drop database'
  task drop: :env do
    db_name = Lux.config(:db_url).split('/').last
    Lux.run "dropdb #{db_name}"
  end

  desc 'Run PSQL console'
  task :console => :env do
    system "psql '%s'" % Lux.config(:db_url)
  end

  desc 'Automigrate schema'
  task am: :env do
    # Sequel extension and plugin test
    DB.run %[DROP TABLE IF EXISTS lux_tests;]
    DB.run %[CREATE TABLE lux_tests (int_array integer[] default '{}', text_array text[] default '{}');]
    class LuxTest < Sequel::Model; end;
    LuxTest.new.save
    die('"DB.extension :pg_array" not loaded') unless LuxTest.first.int_array.class == Sequel::Postgres::PGArray
    DB.run %[DROP TABLE IF EXISTS lux_tests;]

    schema = Pathname.new './config/schema.rb'
    require schema.to_s if schema.exist?

    Lux.config.migrate = true
    require './config/application'
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
    db_name  = Lux.config(:db_url).split('/').last

    Rake::Task['db:drop'].invoke
    Rake::Task['db:create'].invoke
    Lux.run 'psql %s < %s' % [db_name, sql_file]
  end
end
