# Explicit load order for the db plugin.
#
# The framework's Lux::Plugin loader requires this single file; no
# Dir.require_all sweep on the plugin tree. Add new files here.
#
# Layout (all under lib/, required here in order)
#   lib/schema_define.rb - pure Ruby schema DSL additions (no Sequel)
#   lib/ext/      - direct Sequel::Model class/instance/dataset extensions
#   lib/sequel/   - Sequel plugins (loaded for later `plugin :name` registration)
#   lib/migrate/  - schema migration runtime (used by `lux db:am`)

Sequel::Model.require_valid_table = false if Lux.runtime.task_runner?

root = File.expand_path(__dir__)

# --- lib/ : pure-Ruby utilities ----------------------------------------
require_relative 'lib/schema_define'

# --- lib/ext/ : Sequel-aware extensions ------------------------------------
# core defines class+instance helpers; dataset_methods provides the x*
# query primitives used by dataset_scopes, so order matters within ext/.
# nav_models is the Nav <-> model integration, not a Sequel::Model extension.
require_relative 'lib/ext/core'
require_relative 'lib/ext/nav_models'
require_relative 'lib/ext/cache'
require_relative 'lib/ext/dataset_methods'
require_relative 'lib/ext/dataset_scopes'
require_relative 'lib/ext/find_precache'
require_relative 'lib/ext/paginate'
require_relative 'lib/ext/logger'
require_relative 'lib/ext/model_tree'
require_relative 'lib/ext/enums_plugin'

# --- lib/sequel/ : Sequel plugins (defined here, registered in app code)
require_relative 'lib/sequel/_ref_linker'
require_relative 'lib/sequel/hooks'
require_relative 'lib/sequel/before_save_filters'
require_relative 'lib/sequel/create_limit'
require_relative 'lib/sequel/composite_primary_keys'

# --- lib/migrate/ : schema migration runtime ---------------------------
require_relative 'lib/migrate/auto_create_tables' if ENV['DB_MIGRATE'] == 'true'
require_relative 'lib/migrate/auto_migrate'
