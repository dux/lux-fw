module Lux
  def db(name = :main)
    Lux::Db.connection(name)
  end
end
