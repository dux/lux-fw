module Lux
  # Access policy. See lib/lux/policy/.
  #
  #   Lux.policy.can(model: blog, user: user).read?
  #   Lux.policy.current_user
  def policy
    Lux::Policy
  end
end
