# Lux::Type::RefType - the app's ref format as a column type.
#
# The rule is whatever Lux.config.ref_format names (see
# Lux::Application::Nav::Base), so the router, this column type and model
# primary keys cannot drift apart - switching an app to :uuid7 moves the column
# with it. Resolved per call, not at load time, so the Dir.require_all sweep
# order does not matter.
class Lux::Type::RefType < Lux::Type
  def coerce
    value { |data| data.to_s }

    format = Lux::Application::Nav::Base.build(value)

    error_for(:max_length_error, format.db_limit, value.length) if value.length > format.db_limit
    error_for(:unallowed_characters_error) unless format.valid?
  end

  def db_schema
    [:string, { limit: Lux::Application::Nav::Base.build.db_limit }]
  end
end
