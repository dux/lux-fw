require 'test_helper'
require_relative './factories'
require_relative './policies'

describe Lux::Policy do
  def user
    @user ||= factory.create :pol_user
  end

  def admin_user
    @admin_user ||= factory.create :pol_user, is_admin: true
  end

  def post
    @post ||= factory.create :pol_post, created_by: 999
  end

  before do
    Thread.current[:current_user] = nil
  end

  describe 'accessed via proxy' do
    it 'raises custom error' do
      _{ PolApplicationPolicy.can(user: user).custom_error! }.must_raise Lux::Policy::Error
    end

    it 'can write as admin' do
      Thread.current[:current_user] = admin_user
      assert post.can.write?
    end

    it 'cant write as user' do
      Thread.current[:current_user] = user
      _(post.can.write?).must_equal false
    end

    it 'does not break on truthy bang method' do
      Thread.current[:current_user] = admin_user
      assert post.can.write!
    end

    it 'raises error on bang method' do
      Thread.current[:current_user] = user
      _{ post.can.write! }.must_raise Lux::Policy::Error
    end
  end
end
