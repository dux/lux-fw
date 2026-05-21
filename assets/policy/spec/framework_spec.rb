require 'spec_helper'
require_relative './mocks'
require_relative './policies'

class PolFakeController
  include Lux::Policy::Controller
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
  let(:controller)  { PolFakeController.new }
  let!(:post)       { mock.create :pol_post }
  let!(:admin_user) { mock.create :pol_user, is_admin: true }

  before do
    Thread.current[:current_user] = nil
  end

  context 'authorize checks if' do
    it 'is_authorized? is false' do
      expect(controller.is_authorized?).to be false
    end

    it 'accepts block as an argument' do
      Thread.current[:current_user] = admin_user
      controller.authorize { true }
      expect(controller.is_authorized?).to be true
    end

    it 'accepts only true as an argument' do
      controller.authorize(true)
      expect(controller.is_authorized?).to be true
    end

    it 'fails on is_authorized! bang check' do
      expect { controller.is_authorized! }.to raise_error Lux::Policy::Error
    end

    it 'fails on false pass' do
      expect { controller.authorize(false) }.to raise_error Lux::Policy::Error
    end
  end

  context 'model checks' do
    let(:user) { PolUser.new 1, 'Dux', 'dux@foo.bar', true }

    it 'checks if it can work trough model' do
      expect(PolMocvara.new.can(user).admin?).to eq(true)
    end

    it 'checks if it can access current user' do
      Thread.current[:current_user] = user
      expect(PolMocvara.new.can.admin?).to eq(true)
    end
  end

  context 'lux controller is wired with policy adapter' do
    it 'has authorize / is_authorized? on Lux::Controller' do
      expect(Lux::Controller.include?(Lux::Policy::Controller)).to be true
    end
  end
end
