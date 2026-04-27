Lux::Db.boot!

Sequel::Model.require_valid_table = false if Lux.env.rake?

Dir.require_all __dir__
