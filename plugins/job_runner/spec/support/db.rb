# Shared job_runner spec bootstrap: a test DB, the lux_jobs table and the
# plugin load (LuxJob, LuxJobLock). Required by every job_runner spec so they
# can run in one process without redefining DB / reloading the plugin.

require 'test_helper'

# --- DB bootstrap ---------------------------------------------------------
Object.send(:remove_const, :DB) if defined?(DB)
DB ||= Sequel.connect('postgres:///lux_fw_test')
DB.extension :pg_array, :pg_json
DB.loggers.clear

# Load just enough of the db plugin to get the schema DSL, hooks and enums.
require_relative '../../../db/loader.rb'
Sequel::Model.plugin :lux_schema
Sequel::Model.plugin :lux_hooks
Sequel::Model.plugin :lux_before_save

# Host-level ApplicationModel stand-in: ref primary key with auto-fill.
unless defined?(ApplicationModel)
  ApplicationModel = Class.new(Sequel::Model) do
    set_primary_key :ref
    unrestrict_primary_key
    plugin :lux_schema

    def before_create
      self[:ref] ||= Lux::Utils::Ref.generate
      super
    end
  end
end

# Fresh table for each run, matching the LuxJob schema.
DB.drop_table?(:lux_jobs)

DB.create_table :lux_jobs do
  String  :ref, primary_key: true
  String  :name
  jsonb   :opts, default: Sequel.lit("'{}'::jsonb"), null: false
  Integer :retry_count, default: 0
  Time    :run_at, index: true
  String  :status_sid, size: 1, default: 's'
  String  :response, text: true
  Time    :created_at
  Time    :updated_at
end

# job.log writes through Lux.logger(:lux_job); keep it off disk.
Lux::LOGGER_CACHE[:lux_job] = Logger.new(IO::NULL)

# Sweeps load/ (LuxJob, LuxJobLock); guard so several specs can share this file.
Lux::Plugin.load File.expand_path('../..', __dir__) unless defined?(LuxJob)
