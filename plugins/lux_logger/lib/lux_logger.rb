class LuxLogger < ApplicationModel
  schema do
    name
    opts Hash
    creator_ref
    created_at Time
  end

  class << self
    def log name, opts = {}
      create(
        name: name.to_s,
        opts: opts
      )
    end
  end

  def admin_path
    "/admin/lux_loggers/#{sid}"
  end
end
