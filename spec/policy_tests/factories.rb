PolUser ||= Struct.new(:id, :name, :email, :is_admin)
PolPost ||= Struct.new(:id, :created_by, :name)

factory :pol_user do |user, opts|
  user.id       = sequence :pol_user_id
  user.name     = opts[:name]     || "user-#{sequence(:pol_user_name)}"
  user.email    = opts[:email]    || "user#{sequence(:pol_user_email)}@example.com"
  user.is_admin = opts[:is_admin] || false
end

factory :pol_post do |post, opts|
  post.id          = sequence :pol_post_id
  post.name        = opts[:name]       || "post-#{sequence(:pol_post_name)}"
  post.created_by  = opts[:created_by] || sequence(:pol_post_creator)

  def post.can user = nil
    Lux::Policy.can(user: user, model: self)
  end
end
