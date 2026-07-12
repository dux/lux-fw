require 'test_helper'
require_relative '../../plugins/web_common/load/lib/user_session'

describe UserSession do
  def with_user_lookup result, find: nil
    had_user = Object.const_defined?(:User)
    original_user = User if had_user
    Object.send(:remove_const, :User) if had_user

    user_class = Class.new
    user_class.define_singleton_method(:find_by) { |**_opts| result }
    user_class.define_singleton_method(:find) { |_ref| find }
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
    user = Struct.new(:ref, :api_key).new('usr-1', 'valid-key')

    with_user_lookup user, find: user do
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

  it 'caches api key -> ref and reloads via User.find on the next call' do
    user = Struct.new(:ref, :api_key).new('usr-1', 'valid-key')
    Lux.cache.delete UserSession.send(:api_key_cache_key, 'valid-key')

    with_user_lookup user, find: user do
      without_real_sleep do |delays|
        assert_equal user, UserSession.api_key_load('valid-key')
        assert_empty delays

        User.define_singleton_method(:find_by) { |**_opts| raise 'should not hit db' }
        assert_equal user, UserSession.api_key_load('valid-key')
        assert_empty delays
      end
    end
  ensure
    Lux.cache.delete UserSession.send(:api_key_cache_key, 'valid-key')
  end

  it 'drops a stale cache entry when the key no longer matches the user' do
    user = Struct.new(:ref, :api_key).new('usr-1', 'new-key')
    cache_key = UserSession.send(:api_key_cache_key, 'old-key')
    Lux.cache.set cache_key, user.ref, 60

    with_user_lookup nil, find: user do
      without_real_sleep do |delays|
        assert_nil UserSession.api_key_load('old-key')
        assert_equal [0.2], delays
        assert_nil Lux.cache.get(cache_key)
      end
    end
  end
end
