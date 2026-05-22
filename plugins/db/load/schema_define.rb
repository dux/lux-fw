# DB-related extensions to the Lux::Schema::Define DSL.
#
# Only loaded with `Lux.plugin :db`, since the helpers below describe
# database columns / migrations.

module Lux
  class Schema
    class Define
      # `timestamps` inside `schema do ... end` adds the canonical audit
      # quartet: created_at, updated_at, creator_ref, updater_ref.
      # Host app is expected to register Lux::Type::UlidType.
      def timestamps
        created_at Time
        updated_at Time
        creator_ref :ulid
        updater_ref :ulid
      end
    end
  end
end
