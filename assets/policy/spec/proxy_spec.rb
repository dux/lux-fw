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

  context 'accessed via proxy' do
    it 'raises custom error' do
      expect { PolApplicationPolicy.can(user: user).custom_error! }.to raise_error Lux::Policy::Error
    end

    it 'can write as admin' do
      Thread.current[:current_user] = admin_user
      expect(post.can.write?).to be_truthy
    end

    it 'cant write as user' do
      Thread.current[:current_user] = user
      expect(post.can.write?).to be_falsy
    end

    it 'does not break on truthy bang method' do
      Thread.current[:current_user] = admin_user
      expect(post.can.write!).to be_truthy
    end

    it 'raises error on bang method' do
      Thread.current[:current_user] = user
      expect { post.can.write! }.to raise_error Lux::Policy::Error
    end
  end
end
