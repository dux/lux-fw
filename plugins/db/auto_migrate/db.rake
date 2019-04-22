namespace :db do
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
end