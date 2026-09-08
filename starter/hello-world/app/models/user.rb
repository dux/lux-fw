class User < ApplicationModel
  schema do
    email          :email, index: true
    name?          String, max: 100
    is_locked      false
    is_deleted     false
    cached_avatar? String
    last_login?    Time
    timestamps
  end

  def self.quick_create email
    email = email.downcase
    first(email: email) || begin
      user = new(email: email)
      # A self-registering user owns their initial audit fields.
      user[:ref] = user[:creator_ref] = user[:updater_ref] = Lux::Utils::Ref.generate
      user.save
    end
  end
end
