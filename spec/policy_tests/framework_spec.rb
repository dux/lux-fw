require 'test_helper'
require_relative './factories'
require_relative './policies'

class PolFakeAuthorize
  include Lux::Policy::Authorize
end

class PolMocvara
  include Lux::Policy::Model
end

class PolMocvaraPolicy < Lux::Policy
  def admin?
    user.is_admin
  end
end

describe Lux::Policy do
  def router
    @router ||= PolFakeAuthorize.new
  end

  def post
    @post ||= factory.create :pol_post
  end

  def admin_user
    @admin_user ||= factory.create :pol_user, is_admin: true
  end

  before do
    Thread.current[:current_user] = nil
    post
    admin_user
  end

  describe 'authorize checks if' do
    it 'is_authorized? is false' do
      _(router.is_authorized?).must_equal false
    end

    it 'accepts block as an argument' do
      Thread.current[:current_user] = admin_user
      router.authorize { true }
      _(router.is_authorized?).must_equal true
    end

    it 'accepts only true as an argument' do
      router.authorize(true)
      _(router.is_authorized?).must_equal true
    end

    it 'fails on is_authorized! bang check' do
      _{ router.is_authorized! }.must_raise Lux::Policy::Error
    end

    it 'fails on false pass' do
      _{ router.authorize(false) }.must_raise Lux::Policy::Error
    end
  end

  describe 'model checks' do
    def user
      @user ||= PolUser.new 1, 'Dux', 'dux@foo.bar', true
    end

    it 'checks if it can work trough model' do
      _(PolMocvara.new.can(user).admin?).must_equal true
    end

    it 'checks if it can access current user' do
      Thread.current[:current_user] = user
      _(PolMocvara.new.can.admin?).must_equal true
    end
  end
end
