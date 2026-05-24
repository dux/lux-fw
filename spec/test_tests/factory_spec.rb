require 'test_helper'

# Ported from clean-mock 0.2.3 spec/tests/clean_spec.rb so we catch
# regressions in the vendored copy.

class CMTestUser
  attr_accessor :name, :email, :is_admin, :org_id, :custom_org_id, :is_saved
  def save; @is_saved = true; end
end

class CMTestOrg
  attr_accessor :is_saved
  def id; 11; end
  def save; @is_saved = true; end
end

factory do
  define :cm_test_user, class: CMTestUser do |user, opts|
    user.name     = 'User %s' % sequence(:cm_test_user)
    user.email    = opts[:email] || 'u%s@test.com' % sequence
    user.is_admin = false

    func(:say_ok) { 'ok' }
    def user.say_not_ok; 'not ok'; end

    trait(:admin)    { user.is_admin = true }
    trait(:with_org) { create :cm_test_org, 'org_id' }

    if opts[:process_after_save]
      after_save do
        func(:after_save_test) { true }
      end
    end
  end

  define :cm_admin_user, class: CMTestUser do |user, _opts|
    user.is_admin = true
  end

  define(:cm_test_org, class: CMTestOrg) {}
end

factory.define(:cm_random_name, class: false) { ['John', 'Josh', 'Mike'].sample }

factory :cm_foo, class: false do
  Class.new { def foo; :bar; end }.new
end

describe Lux::Test::Factory do
  describe 'failures' do
    it 'raises ArgumentError for unknown mock' do
      _{ factory.build(:totally_unknown_mock) }.must_raise ArgumentError
    end

    it 'lists known mocks in the error message' do
      e = _{ factory.build(:totally_unknown_mock) }.must_raise ArgumentError
      _(e.message).must_match(/Known:/)
    end
  end

  describe 'build' do
    it 'auto-instantiates the class from the mock name' do
      _(factory.build(:cm_test_user).name).must_match(/^User /)
    end

    it 'reads opts and forwards them to the block' do
      _(factory.build(:cm_test_user, email: 'foo@bar').email).must_equal 'foo@bar'
    end

    it 'attaches func methods to the instance' do
      user = factory.build(:cm_test_user)
      _(user).must_be_kind_of CMTestUser
      _(user.say_ok).must_equal 'ok'
      _(user.say_not_ok).must_equal 'not ok'
    end

    it 'applies traits' do
      _(factory.build(:cm_test_user).is_admin).must_equal false
      _(factory.build(:cm_test_user, :admin).is_admin).must_equal true
    end

    it 'links a sibling via create with custom field' do
      user = factory.build(:cm_test_user, :with_org)
      _(user.org_id).must_equal 11
    end
  end

  describe 'explicit class:' do
    it 'uses the given class' do
      _(factory.build(:cm_admin_user)).must_be_kind_of CMTestUser
      _(factory.build(:cm_admin_user).is_admin).must_equal true
    end
  end

  describe 'class: false' do
    it 'returns whatever the block produces' do
      _(factory.build(:cm_foo).foo).must_equal :bar
    end

    it 'works with a plain block return value' do
      list = ['John', 'Josh', 'Mike']
      _(list.include?(factory.build(:cm_random_name))).must_equal true
    end
  end

  describe 'create' do
    it 'calls save when the model responds to it' do
      _(factory.create(:cm_test_org).is_saved).must_equal true
    end

    it 'saves user-style models too' do
      _(factory.create(:cm_test_user).is_saved).must_equal true
    end
  end

  describe 'fetch' do
    it 'returns the same instance for identical args' do
      a = factory.fetch(:cm_test_org)
      b = factory.fetch(:cm_test_org)
      _(a).must_be_same_as b
    end

    it 'returns different instances for different args' do
      a = factory.fetch(:cm_test_user, email: 'a@a.com')
      b = factory.fetch(:cm_test_user, email: 'b@b.com')
      refute_equal a.object_id, b.object_id
    end
  end

  describe 'after_save' do
    it 'does not fire on build' do
      user = factory.build(:cm_test_user, process_after_save: true)
      _(user.respond_to?(:after_save_test)).must_equal false
    end

    it 'fires on create' do
      user = factory.create(:cm_test_user, process_after_save: true)
      _(user.respond_to?(:after_save_test)).must_equal true
    end
  end

  describe 'sequence' do
    it 'starts at start+1 when given a start value' do
      factory.define(:cm_seq_start, class: false) { sequence(:cm_custom_seq, 100) }
      _(factory.build(:cm_seq_start)).must_equal 101
    end

    it 'auto-increments under the default :seq name' do
      factory.define(:cm_seq_default, class: false) { sequence }
      a = factory.build(:cm_seq_default)
      b = factory.build(:cm_seq_default)
      _(b).must_equal a + 1
    end
  end

  describe 'class: :symbol dynamic class creation' do
    it 'creates the constant when missing' do
      factory.define(:cm_dynamic_widget, class: :cm_dynamic_widget) { |_m, _o| }
      _(factory.build(:cm_dynamic_widget).class.name).must_equal 'CmDynamicWidget'
    end
  end

  describe 'trait errors' do
    it 'raises on unknown trait' do
      e = _{ factory.build(:cm_test_user, :nonexistent) }.must_raise RuntimeError
      _(e.message).must_match(/not found/)
    end
  end

  describe 'func overload' do
    it 'last definition wins on the same instance' do
      factory.define(:cm_func_overload, class: CMTestUser) do |_u, _o|
        func(:tag) { 'first' }
        func(:tag) { 'second' }
      end
      _(factory.build(:cm_func_overload).tag).must_equal 'second'
    end
  end
end
