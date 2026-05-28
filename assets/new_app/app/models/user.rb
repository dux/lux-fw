class User < ApplicationModel
  schema do
    email         type: :email, index: true
    name          String, max: 100
    is_locked     Boolean, default: false
    is_deleted    Boolean, default: false
    cached_avatar String
    last_login    Time
    timestamps
  end

  # find-or-create by email - used by the authcog login callback
  def self.quick_create email
    first(email: email) || create(email: email)
  end
end
