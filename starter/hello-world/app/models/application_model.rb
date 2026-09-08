ApplicationModel ||= Sequel::Model(Lux.db)

ApplicationModel.plugin :lux_schema
ApplicationModel.plugin :lux_before_save
ApplicationModel.plugin :lux_links
ApplicationModel.include Lux::Policy::Model

ApplicationModel.class_eval do
  def before_validation
    self[:ref] ||= Lux::Utils::Ref.generate if new?
    super
  end

  def self.current
    Lux.current.var[to_s.underscore]
  end

  def self.current=(object)
    Lux.current.var[to_s.underscore] = object
  end
end
