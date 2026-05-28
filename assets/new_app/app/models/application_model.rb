# Base model: a Sequel::Model bound to the :main database with the Lux
# plugins. Subclass it and declare fields with `schema do ... end`.

ApplicationModel = Sequel::Model(DB)

ApplicationModel.plugin :lux_schema       # schema do ... end
ApplicationModel.plugin :lux_hooks        # before :cud / after :cud
ApplicationModel.plugin :lux_before_save  # created_at / updated_at
ApplicationModel.plugin :lux_links        # link :other
ApplicationModel.plugin :primary_keys     # string ULID :ref primary key

ApplicationModel.class_eval do
  # every row gets a string ULID ref on create
  before :c do
    self[:ref] ||= Lux::Utils::Ref.generate if respond_to?(:ref)
  end

  # request-scoped "current" record, e.g. User.current
  def self.current
    Lux.current.var[to_s.underscore]
  end

  def self.current=(object)
    Lux.current.var[to_s.underscore] = object
  end
end
