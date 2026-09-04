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
    first(email: email) || begin
      # nobody is current during the login callback, so the audit columns have
      # no one to attribute to - a self-registering user is their own creator
      user = new(email: email)
      user[:ref] = user[:creator_ref] = user[:updater_ref] = Lux::Utils::Ref.generate
      user.save
    end
  end
end
