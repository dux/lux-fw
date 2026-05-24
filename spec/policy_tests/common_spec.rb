require 'test_helper'
require_relative './factories'
require_relative './policies'

describe Lux::Policy do
  def post
    @post ||= factory.create :pol_post
  end

  def user
    @user ||= factory.create :pol_user
  end

  def admin_user
    @admin_user ||= factory.create :pol_user, is_admin: true
  end

  before do
    Thread.current[:current_user] = nil
    # force eager creation to match original `let!` semantics
    post
    user
    admin_user
  end

  describe 'without model' do
    it 'cant access admin pages' do
      _{ PolApplicationPolicy.can(user: user).admin! }.must_raise Lux::Policy::Error
    end

    it 'can access admin pages' do
      _(PolApplicationPolicy.can(user: admin_user).admin?).must_equal true
    end

    it 'raises error on action not found' do
      _{ PolApplicationPolicy.can(user: user).not_defined? }.must_raise NoMethodError
    end

    it 'processes before filter' do
      _{ PolApplicationPolicy.can(user: user).before_2! }.must_raise Lux::Policy::Error
    end

    it 'accepts error block in bang method' do
      msg = 'some msg'
      err = _{
        PolApplicationPolicy.can(user: user).admin! { msg }
      }.must_raise Lux::Policy::Error
      _(err.message).must_equal msg
    end

    it 'accepts error block in question method' do
      test = false
      PolApplicationPolicy.can(user: user).admin? { test = true }
      _(test).must_equal true
    end

    it 'accepts symbol as a model' do
      test = PolHeadlessPolicy.can(user: user).read?
      _(test).must_equal true
    end

    it 'checks using user in Thread current' do
      Thread.current[:current_user] = user
      _(PolApplicationPolicy.can.admin?).must_equal false

      Thread.current[:current_user] = admin_user
      _(PolApplicationPolicy.can.admin?).must_equal true
    end
  end

  describe 'with model' do
    it 'cant write not owned object' do
      post = factory.create :pol_post, created_by: user.id + 9
      _(PolPostPolicy.can(model: post, user: user).write?).must_equal false
    end

    it 'can write owned object' do
      post = factory.create :pol_post, created_by: user.id
      _(PolPostPolicy.can(post, user).write?).must_equal true

      post = factory.create :pol_post, created_by: user.id + 9
      _(PolPostPolicy.can(user: admin_user).write?).must_equal true
    end

    it 'accepts a function parameter' do
      _(PolPostPolicy.can(post, user).create?({ip: '1.2.3.4'})).must_equal true
      _{ PolPostPolicy.can(post, user).create!({ip: '2.3.4.5'}) }.must_raise Lux::Policy::Error
    end

    it 'is accessible via can and accepts attributes' do
      _(PolPostPolicy.can(user, post).create?({ip: '1.2.3.4'})).must_equal true
    end
  end
end
