# Explicit load order for the db plugin.
#
# The framework's Lux::Plugin loader requires this single file; no
# Dir.require_all sweep on the plugin tree. Add new files here.
#
# Layout
#   lib/      - pure Ruby utilities (no Sequel)
#   ext/      - direct Sequel::Model class/instance/dataset extensions
#   plugins/  - Sequel plugins (loaded for later `plugin :name` registration)
#   migrate/  - schema migration runtime (used by `lux db:am`)

Sequel::Model.require_valid_table = false if Lux.runtime.rake?

root = File.expand_path(__dir__)

# --- lib/ : pure-Ruby utilities ----------------------------------------
require_relative 'lib/ref'
require_relative 'lib/ref_type'
require_relative 'lib/schema_define'

# --- ext/ : direct Sequel::Model extensions ----------------------------
# core defines class+instance helpers; dataset_methods provides the x*
# query primitives used by dataset_scopes, so order matters within ext/.
require_relative 'ext/core'
require_relative 'ext/cache'
require_relative 'ext/dataset_methods'
require_relative 'ext/dataset_scopes'
require_relative 'ext/find_precache'
require_relative 'ext/paginate'
require_relative 'ext/logger'
require_relative 'ext/model_tree'
require_relative 'ext/enums_plugin'

# --- plugins/ : Sequel plugins (defined here, registered in app code) --
# _ref_linker loads first (underscore prefix) because it const_sets the
# :LuxLinks and :ParentModel aliases that consumer apps register by name.
require_relative 'plugins/_ref_linker'
require_relative 'plugins/hooks'
require_relative 'plugins/before_save_filters'
require_relative 'plugins/create_limit'
require_relative 'plugins/composite_primary_keys'

# --- migrate/ : schema migration runtime -------------------------------
require_relative 'migrate/auto_create_tables'
require_relative 'migrate/auto_migrate'
