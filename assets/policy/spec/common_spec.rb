require 'spec_helper'
require_relative './mocks'
require_relative './policies'

describe Lux::Policy do
  let!(:post)       { mock.create :pol_post }
  let!(:user)       { mock.create :pol_user }
  let!(:admin_user) { mock.create :pol_user, is_admin: true }

  before do
    Thread.current[:current_user] = nil
  end

  context 'without model' do
    it 'cant access admin pages' do
      expect { PolApplicationPolicy.can(user: user).admin! }.to raise_error Lux::Policy::Error
    end

    it 'can access admin pages' do
      expect(PolApplicationPolicy.can(user: admin_user).admin?).to be_truthy
    end

    it 'raises error on action not found' do
      expect { PolApplicationPolicy.can(user: user).not_defined? }.to raise_error NoMethodError
    end

    it 'processes before filter' do
      expect{ PolApplicationPolicy.can(user: user).before_2! }.to raise_error Lux::Policy::Error
    end

    it 'accepts error block in bang method' do
      msg = 'some msg'
      expect{
        PolApplicationPolicy.can(user: user).admin! { msg }
      }.to raise_error(Lux::Policy::Error, msg)
    end

    it 'accepts error block in question method' do
      test = false
      PolApplicationPolicy.can(user: user).admin? { test = true }
      expect(test).to be_truthy
    end

    it 'accepts symbol as a model' do
      test = PolHeadlessPolicy.can(user: user).read?
      expect(test).to be_truthy
    end

    it 'checks using user in Thread current' do
      Thread.current[:current_user] = user
      expect(PolApplicationPolicy.can.admin?).to eq(false)

      Thread.current[:current_user] = admin_user
      expect(PolApplicationPolicy.can.admin?).to eq(true)
    end
  end

  context 'with model' do
    it 'cant write not owned object' do
      post = mock.create :pol_post, created_by: user.id + 9
      expect(PolPostPolicy.can(model: post, user: user).write?).to be_falsy
    end

    it 'can write owned object' do
      post = mock.create :pol_post, created_by: user.id
      expect(PolPostPolicy.can(post, user).write?).to be_truthy

      post = mock.create :pol_post, created_by: user.id + 9
      expect(PolPostPolicy.can(user: admin_user).write?).to be_truthy
    end

    it 'accepts a function parameter' do
      expect( PolPostPolicy.can(post, user).create?({ip: '1.2.3.4'}) ).to be_truthy
      expect { PolPostPolicy.can(post, user).create!({ip: '2.3.4.5'}) }.to raise_error Lux::Policy::Error
    end

    it 'is accessible via can and accepts attributes' do
      expect(PolPostPolicy.can(user, post).create?({ip: '1.2.3.4'})).to be_truthy
    end
  end
end
