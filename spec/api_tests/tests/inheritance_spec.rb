require 'test_helper'
require_relative '../loader'

describe 'inheritance and super!' do
  describe 'method inheritance' do
    it 'inherits methods from parent class' do
      # UserApi inherits from ModelApi which has member :creator
      response = UserApi.render :creator, id: 1, params: { show_all: false }
      _(response[:success]).must_equal true
      _(response[:data]).must_equal '@dux'
    end

    it 'inherits collection methods' do
      # UserApi collection :call_me_in_child overrides ModelApi
      # but still inherits the base implementation
      response = UserApi.render :call_me_in_child
      _(response[:success]).must_equal true
      _(response[:data]).must_equal 4690  # 2345 * 2
    end

    it 'inherits member methods' do
      response = UserApi.render :call_me_in_child, id: 1
      _(response[:success]).must_equal true
      _(response[:data]).must_equal 2468  # 1234 * 2
    end
  end

  describe 'super! method' do
    it 'calls parent implementation via super!' do
      # UserApi collection :call_me_in_child calls super! * 2
      # ModelApi :call_me_in_child sets @number = 2345
      response = UserApi.render :call_me_in_child
      _(response[:data]).must_equal 4690  # 2345 * 2
    end

    it 'calls parent member method via super!' do
      # UserApi member :call_me_in_child calls super! and then @number * 2
      # ModelApi member :call_me_in_child sets @number = 1234
      response = UserApi.render :call_me_in_child, id: 1
      _(response[:data]).must_equal 2468  # 1234 * 2
    end
  end

  describe 'opts inheritance' do
    it 'inherits method options from ancestors' do
      # CompanyApi inherits from ModelApi which has :creator method
      opts = CompanyApi.opts
      refute_nil opts[:member][:creator]
      assert opts[:member][:creator][:desc]  # has some description
    end

    it 'child can override parent method options' do
      # Check that child opts take precedence
      child_opts = UserApi.opts
      parent_opts = ModelApi.opts

      # Both should have call_me_in_child but with different allow values
      _(child_opts[:collection][:call_me_in_child][:allow]).must_equal ['DELETE']
    end
  end

  describe 'callback inheritance' do
    it 'inherits before callbacks from ancestors' do
      # ApplicationApi before sets @_time
      # This should run for all descendants
      response = CompanyApi.render :show, id: 1
      _(response[:success]).must_equal true
    end

    it 'inherits after callbacks from ancestors' do
      # ApplicationApi after sets :ip meta
      response = CompanyApi.render :show, id: 1
      _(response[:meta][:ip]).must_equal '1.2.3.4'
    end
  end

  describe 'module inclusion' do
    it 'includes methods from classic module' do
      response = GenericApi.render :module_clasic
      _(response[:success]).must_equal true
      _(response[:data]).must_equal 'is_module'
    end
  end

  describe 'plugin inheritance' do
    it 'includes methods from plugin' do
      response = GenericApi.render :plugin_test
      _(response[:success]).must_equal true
      _(response[:data]).must_equal 'from_plugin'
    end
  end
end
