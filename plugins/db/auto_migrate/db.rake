require 'uri'

def db_name_from_url url
  URI.parse(url).path.sub('/', '')
end

def db_backup_file_location name
  folder = './tmp/db_dump'
  Dir.mkdir(folder) unless Dir.exist?(folder)
  "%s/%s.sql" % [folder, name]
end

def dev_check!
  if Lux.env.prod?
    puts "Refused: destructive DB operations are not allowed in production".colorize(:red)
    exit 1
  end
end

def load_migrate_file file, external: false
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

###

namespace :db do
  desc 'Show configured databases'
  task :info => :env do
    Lux::Db.configured_names.each do |name|
      url = Lux::Db.url_for(name)
      db_name = db_name_from_url(url)
      exists = system("psql -lqt | cut -d \\| -f 1 | grep -qw #{db_name}")
      status = exists ? 'exists'.colorize(:green) : 'missing'.colorize(:red)
      puts "  :%-10s %s (%s)" % [name, db_name, status]
    end
  end

  desc 'Create databases if missing'
  task :create => :env do
    Lux::Db.configured_names.each do |name|
      db_name = db_name_from_url(Lux::Db.url_for(name))

      if system("psql -lqt | cut -d \\| -f 1 | grep -qw #{db_name}")
        puts "Database '#{db_name}' already exists".colorize(:yellow)
      else
        Lux.run "createdb %s" % db_name
        puts "Database '#{db_name}' created".colorize(:green)
      end
    end
  end

  desc 'Drop databases (including test)'
  task :drop => :env do
    dev_check!

    Lux::Db.disconnect_all

    Lux::Db.configured_names.each do |name|
      db_name = db_name_from_url(Lux::Db.url_for(name))

      for db in [db_name + '_test', db_name]
        if system("psql -lqt | cut -d \\| -f 1 | grep -qw #{db}")
          system "dropdb %s" % db
          puts "Database '#{db}' dropped".colorize(:green)
        else
          puts "Database '#{db}' does not exist, skipping".colorize(:yellow)
        end
      end
    end
  end

  desc 'Drop, create and auto migrate databases'
  task :reset => :env do
    dev_check!
    for task in %w[db:drop db:create db:am]
      Rake::Task[task].reenable
      Rake::Task[task].invoke
    end
  end

  desc 'Dump/backup databases to SQL'
  task :backup => :env do
    Lux::Db.configured_names.each do |name|
      url = Lux::Db.url_for(name)
      db_name = db_name_from_url(url)
      sql_file = db_backup_file_location db_name
      Lux.run "pg_dump --no-privileges --no-owner '#{url}' > #{sql_file}"
      puts "Backed up '#{db_name}' to #{sql_file}".colorize(:green)
      system 'ls -lh %s' % sql_file
    end
  end

  desc 'Restore databases from SQL backup'
  task :restore => :env do
    dev_check!

    Lux::Db.disconnect_all

    Lux::Db.configured_names.each do |name|
      url = Lux::Db.url_for(name)
      db_name = db_name_from_url(url)
      sql_file = db_backup_file_location db_name

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

  namespace :create do
    desc 'Recreate test DBs (drop if exists, copy schema from main, run db:am if main missing)'
    task :test => :env do
      Lux::Db.configured_names.each do |name|
        url = Lux::Db.url_for(name)
        source_db = db_name_from_url(url)
        test_db = source_db + '_test'

        # drop test db if exists
        if system("psql -lqt | cut -d \\| -f 1 | grep -qw #{test_db}")
          system 'dropdb %s' % test_db
          puts "Test database '#{test_db}' dropped".colorize(:yellow)
        end

        # if main db does not exist, create it and run db:am
        unless system("psql -lqt | cut -d \\| -f 1 | grep -qw #{source_db}")
          puts "Main database '#{source_db}' missing, creating and running db:am".colorize(:yellow)
          system 'createdb %s' % source_db
          Rake::Task['db:am'].reenable
          Rake::Task['db:am'].invoke
        end

        system 'createdb %s' % test_db
        system 'pg_dump --schema-only --no-owner --no-privileges %s | psql -q %s > /dev/null 2>&1' % [source_db, test_db]
        puts "Test database '#{test_db}' created (schema from #{source_db})".colorize(:green)
      end
    end
  end

  namespace :drop do
    desc 'Drop test databases'
    task :test => :env do
      Lux::Db.configured_names.each do |name|
        url = Lux::Db.url_for(name)
        test_db = db_name_from_url(url) + '_test'

        if system("psql -lqt | cut -d \\| -f 1 | grep -qw #{test_db}")
          system 'dropdb %s' % test_db
          puts "Test database '#{test_db}' dropped".colorize(:green)
        else
          puts "Test database '#{test_db}' does not exist".colorize(:yellow)
        end
      end
    end
  end

  desc 'Load seed from ./db/seeds'
  task :seed => :env do
    dev_check!

    Lux::Db.disconnect_all

    Rake::Task['db:reset'].reenable
    Rake::Task['db:reset'].invoke

    require './config/app'

    load_migrate_file './db/seed.rb' do
      for file in Dir['db/seeds/*.rb'].sort
        puts 'Seed: %s' % file.colorize(:green)
        load file
      end
    end
  end

  desc 'Generate seeds'
  task :gen_seeds, [:klass, :ref] => :app do |_, args|
    Lux.die 'argument not given => rake db:gen_seeds[model]' unless args[:klass]

    klass = args[:klass].classify.constantize
    data = klass.xwhere(ref: args[:ref]).limit(100).all.map(&:seed)
      .join("\n\n")

    puts data
  end

  desc 'Run PSQL console'
  task :console, [:name] => :env do |_, args|
    name = (args[:name] || :main).to_sym
    url = Lux::Db.url_for(name)

    unless url
      puts "Database :#{name} not configured".colorize(:red)
      exit 1
    end

    system "psql '%s'" % url
  end

  desc 'Automigrate schema (pass y to auto-confirm column drops: db:am[y])'
  task :am, [:confirm] => :env do |_, args|
    ENV['DB_MIGRATE'] = 'true' unless ENV['DB_MIGRATE'] == 'true'

    load '%s/auto_migrate/auto_migrate.rb' % Lux::Plugin.get('db').folder
    AutoMigrate.auto_confirm = args[:confirm] == 'y'

    DB.run %[DROP TABLE IF EXISTS lux_tests;]
    DB.run %[CREATE TABLE lux_tests (int_array integer[] default '{}');]
    DB.run %[INSERT INTO lux_tests DEFAULT VALUES;]
    row = DB[:lux_tests].first
    die('"DB.extension :pg_array" not loaded') unless row[:int_array].is_a?(Sequel::Postgres::PGArray)
    DB.run %[DROP TABLE IF EXISTS lux_tests;]

    load_migrate_file './db/before.rb'
    load_migrate_file './db/auto_migrate.rb'

    # re-apply schemas for models loaded before AutoMigrate was defined (e.g. plugin models)
    Typero.schema(type: :model).each do |klass_name|
      AutoMigrate.apply_schema klass_name
    end

    load_migrate_file './db/after.rb', external: true
  end
end
