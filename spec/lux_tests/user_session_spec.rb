require 'test_helper'
require_relative '../../plugins/web_common/load/lib/user_session'

describe UserSession do
  def with_user_lookup result
    had_user = Object.const_defined?(:User)
    original_user = User if had_user
    Object.send(:remove_const, :User) if had_user

    user_class = Class.new
    user_class.define_singleton_method(:find_by) { |**_opts| result }
    Object.const_set(:User, user_class)
    yield
  ensure
    Object.send(:remove_const, :User)
    Object.const_set(:User, original_user) if had_user
  end

  def without_real_sleep
    delays = []
    UserSession.define_singleton_method(:sleep) { |seconds| delays.push seconds }
    yield delays
  ensure
    UserSession.singleton_class.send(:remove_method, :sleep)
  end

  it 'delays a rejected API key by 200 milliseconds' do
    with_user_lookup nil do
      without_real_sleep do |delays|
        assert_nil UserSession.api_key_user('wrong-key')
        assert_equal [0.2], delays
      end
    end
  end

  it 'does not delay a valid API key' do
    user = Object.new

    with_user_lookup user do
      without_real_sleep do |delays|
        assert_equal user, UserSession.api_key_user('valid-key')
        assert_empty delays
      end
    end
  end

  it 'does not delay when no API key was supplied' do
    without_real_sleep do |delays|
      assert_nil UserSession.api_key_user(nil)
      assert_empty delays
    end
  end
end
