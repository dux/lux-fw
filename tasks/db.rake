namespace :db do
  desc 'Automigrate schema'
  task :am do
    load Lux.fw_root.join('./tasks/lib/auto_migrate.rb').to_s

    # load app config
    envs = ['./config/environment.rb', './config/db.rb']
    file = envs.find{ |f| File.exist?(f) } || LuxCli.die('DB ENV not found in %s' % envs.join(' or '))

    load file

    # Sequel extension and plugin test
    DB.run %[DROP TABLE IF EXISTS lux_tests;]
    DB.run %[CREATE TABLE lux_tests (int_array integer[] default '{}', text_array text[] default '{}');]
    class LuxTest < Sequel::Model; end;
    LuxTest.new.save
    die('"DB.extension :pg_array" not loaded') unless LuxTest.first.int_array.class == Sequel::Postgres::PGArray
    DB.run %[DROP TABLE IF EXISTS lux_tests;]

    require './config/schema.rb'
  end
end