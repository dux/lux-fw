def db_backup_file_location name
  folder = './tmp/db_dump'
  Dir.mkdir(folder) unless Dir.exist?(folder)
  name = name.split('/').last if name.include?('/')
  "%s/%s.sql" % [folder, name]
end

def load_file file, external: false
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

def dev_check!
  unless Lux.env.dev?
    print "Sure do DROP DB (Lux ENV: #{Lux.env})? (y/N): "
    exit unless STDIN.gets.chomp.downcase == 'y'
  end
end

db_name = Lux.config.db_url.split('/').last

###

namespace :db do
  desc 'Dump/backup database backups in raw SQL'
  task :backup, [:name] => :env do |_, args|
    for db in Lux.config.sequel_dbs
      sql_file = db_backup_file_location db.opts[:database]
      Lux.run "pg_dump --no-privileges --no-owner --no-reconnect #{db.uri} > #{sql_file}"
      system 'ls -lh %s' % sql_file
    end
  end

  desc 'Restore database backups'
  task :restore, [:name] => :env do |_, args|
    dev_check!

    invoke 'db:drop'

    for db in Lux.config.sequel_dbs
      db_name = db.opts[:database]
      sql_file = db_backup_file_location db_name
      Lux.run 'psql %s < %s' % [db_name, sql_file]
    end
  end

  desc 'Drop databases'
  task :drop do
    dev_check!

    for db in Lux.config.sequel_dbs
      db.disconnect
      Lux.run "dropdb %s" % db.opts[:database]
      Lux.run "createdb %s" % db.opts[:database]
    end
  end

  desc 'Prepare DBs for testing'
  task :test do
    for db in Lux.config.sequel_dbs
      db_name = db.opts[:database]
      test_db_name = db_name + '_test'
      db.run 'drop database if exists %s' % test_db_name
      db.run 'create database %s template %s' % [test_db_name, db_name]
      puts "Prepared #{test_db_name}"
    end
  end

  desc 'Load seed from ./db/seeds '
  task :seed do
    dev_check!

    for db in Lux.config.sequel_dbs
      db.disconnect
    end

    run 'rake db:drop'
    run 'rake db:am'

    require './config/app'

    load_file './db/seed.rb' do
      for file in Dir['db/seeds/*'].sort
        puts 'Seed: %s' % file.colorize(:green)
        # Lux.run "bundle exec lux e #{file}"
        load file
      end
    end
  end

  # rake db:gen_seeds[site]
  # Site.create({
  #   name: "Main site",
  #   org_id: @org.id
  # })
  desc 'Generate seeds'
  task :gen_seeds, [:klass, :ref] => :app do |_, args|
    Lux.die 'arguemnt not given => rake db:gen_seeds[model]' unless args[:klass]

    klass = args[:klass].classify.constantize
    data = klass.xwhere(ref: args[:ref]).limit(100).all.map(&:seed)
      .join("\n\n")

    puts data
  end

  desc 'Run PSQL console'
  task :console do
    system "psql '%s'" % Lux.config.db_url
  end

  desc 'Automigrate schema (pass y to auto-confirm column drops: db:am[y])'
  task :am, [:confirm] do |_, args|
    # ENV['DB_MIGRATE'] should be set in Rakefile before config loads
    ENV['DB_MIGRATE'] = 'true' unless ENV['DB_MIGRATE'] == 'true'

    # load AutoMigrate class
    load '%s/auto_migrate/auto_migrate.rb' % Lux::Plugin.get('db').folder
    AutoMigrate.auto_confirm = args[:confirm] == 'y'

    # verify pg_array extension works (raw SQL to avoid Sequel plugin conflicts)
    DB.run %[DROP TABLE IF EXISTS lux_tests;]
    DB.run %[CREATE TABLE lux_tests (int_array integer[] default '{}');]
    DB.run %[INSERT INTO lux_tests DEFAULT VALUES;]
    row = DB[:lux_tests].first
    die('"DB.extension :pg_array" not loaded') unless row[:int_array].is_a?(Sequel::Postgres::PGArray)
    DB.run %[DROP TABLE IF EXISTS lux_tests;]

    # run app migrations: before -> load models (triggers auto_migrate) -> after
    load_file './db/before.rb'
    load_file './db/auto_migrate.rb'
    load_file './db/after.rb', external: true
  end
end
