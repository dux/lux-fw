require 'test_helper'
require_relative '../loader'

describe 'define block syntax' do
  before do
    unless defined?(DefineTestApi)
      class DefineTestApi < ApplicationApi
        define :simple_define do
          proc { 'simple' }
        end

        define :with_params do
          params do
            name String
            age? Integer
          end
          proc do
            { name: params.name, age: params.age }
          end
        end

        define :with_desc do
          desc 'A described method'
          detail 'More details here'
          proc { 'described' }
        end

        define :with_annotations do
          unsafe
          proc { @api.opts.unsafe }
        end

        ref do
          define :member_define do
            proc { "member_#{@ref}" }
          end

          define :with_allow do
            allow :get
            proc { 'allowed' }
          end

          define :with_multi_allow do
            allow :get, :put
            proc { 'multi_allowed' }
          end
        end
      end
    end
  end

  it 'works with simple define block' do
    response = DefineTestApi.render :simple_define
    _(response[:success]).must_equal true
    _(response[:data]).must_equal 'simple'
  end

  it 'works with params in define block' do
    response = DefineTestApi.render :with_params, params: { name: 'John', age: 30 }
    _(response[:success]).must_equal true
    _(response[:data][:name]).must_equal 'John'
    _(response[:data][:age]).must_equal 30
  end

  it 'validates required params in define block' do
    response = DefineTestApi.render :with_params, params: { age: 30 }
    _(response[:success]).must_equal false
  end

  it 'stores desc and detail from define block' do
    opts = DefineTestApi.opts
    _(opts[:collection][:with_desc][:desc]).must_equal 'A described method'
    _(opts[:collection][:with_desc][:detail]).must_equal 'More details here'
  end

  it 'works with unsafe annotation in define block' do
    opts = DefineTestApi.opts
    _(opts[:collection][:with_annotations][:unsafe]).must_equal true
  end

  it 'works with member define block' do
    response = DefineTestApi.render :member_define, id: 123
    _(response[:success]).must_equal true
    _(response[:data]).must_equal 'member_123'
  end

  it 'stores allow from define block' do
    opts = DefineTestApi.opts
    _(opts[:member][:with_allow][:allow]).must_equal ['GET']
  end

  it 'stores multiple allows from allow :get, :put' do
    opts = DefineTestApi.opts
    _(opts[:member][:with_multi_allow][:allow]).must_equal ['GET', 'PUT']
  end

  it 'existing define in CompanyApi works' do
    response = CompanyApi.render.foo(1, bar: 5)
    _(response[:data]).must_equal 15
  end
end

describe 'define block with def_registration_strict false' do
  before do
    unless defined?(StrictFalseDefineApi)
      class StrictFalseDefineApi < ApplicationApi
        def_registration_strict false

        define :open_action do
          desc 'Anonymous action'
          unsafe
          params do
            name String
          end
          proc { 'open' }
        end
      end
    end
  end

  # Regression: define_method inside define_single_action fires method_added,
  # and with strict registration off that callback used to re-register the
  # action with empty opts, wiping unsafe/desc/params. Guard keeps them.
  it 'keeps unsafe/desc/params when def_registration_strict is false' do
    opts = StrictFalseDefineApi.opts
    _(opts[:collection][:open_action][:unsafe]).must_equal true
    _(opts[:collection][:open_action][:desc]).must_equal 'Anonymous action'
    _(opts[:collection][:open_action][:params]).wont_be_nil
  end

  it 'still runs the action body' do
    response = StrictFalseDefineApi.render :open_action, params: { name: 'x' }
    _(response[:success]).must_equal true
    _(response[:data]).must_equal 'open'
  end
end

describe 'RESTful define syntax' do
  before do
    unless defined?(RestfulDefineApi)
      class RestfulDefineApi < ApplicationApi
        # define get: :action syntax
        define get: :rest_get do
          proc { 'rest_get_result' }
        end

        define post: :rest_post do
          proc { 'rest_post_result' }
        end

        define put: :rest_put do
          proc { 'rest_put_result' }
        end

        define delete: :rest_delete do
          proc { 'rest_delete_result' }
        end

        # define :action, allow: :method syntax
        define :allow_get, allow: :get do
          proc { 'allow_get_result' }
        end

        define :allow_put, allow: :put do
          proc { 'allow_put_result' }
        end

        # multiple HTTP methods for same action
        define [:get, :put] => :multi_method do
          proc { 'multi_method_result' }
        end

        define :multi_allow, allow: [:get, :delete] do
          proc { 'multi_allow_result' }
        end

        ref do
          define get: :member_rest_get do
            proc { "member_#{@ref}" }
          end

          define :member_allow_get, allow: :get do
            proc { "member_allow_#{@ref}" }
          end

          define [:get, :put, :delete] => :member_multi do
            proc { "member_multi_#{@ref}" }
          end
        end
      end
    end
  end

  describe 'define http: :action syntax' do
    it 'works with get: :action' do
      response = RestfulDefineApi.render :rest_get
      _(response[:success]).must_equal true
      _(response[:data]).must_equal 'rest_get_result'
    end

    it 'stores GET method for get: :action' do
      opts = RestfulDefineApi.opts
      _(opts[:collection][:rest_get][:allow]).must_equal ['GET']
    end

    it 'works with post: :action' do
      response = RestfulDefineApi.render :rest_post
      _(response[:success]).must_equal true
      _(response[:data]).must_equal 'rest_post_result'
    end

    it 'stores POST method for post: :action' do
      opts = RestfulDefineApi.opts
      _(opts[:collection][:rest_post][:allow]).must_equal ['POST']
    end

    it 'works with put: :action' do
      response = RestfulDefineApi.render :rest_put
      _(response[:success]).must_equal true
    end

    it 'stores PUT method for put: :action' do
      opts = RestfulDefineApi.opts
      _(opts[:collection][:rest_put][:allow]).must_equal ['PUT']
    end

    it 'works with delete: :action' do
      response = RestfulDefineApi.render :rest_delete
      _(response[:success]).must_equal true
    end

    it 'stores DELETE method for delete: :action' do
      opts = RestfulDefineApi.opts
      _(opts[:collection][:rest_delete][:allow]).must_equal ['DELETE']
    end
  end

  describe 'define :action, allow: :method syntax' do
    it 'works with allow: :get' do
      response = RestfulDefineApi.render :allow_get
      _(response[:success]).must_equal true
      _(response[:data]).must_equal 'allow_get_result'
    end

    it 'stores GET method for allow: :get' do
      opts = RestfulDefineApi.opts
      _(opts[:collection][:allow_get][:allow]).must_equal ['GET']
    end

    it 'works with allow: :put' do
      response = RestfulDefineApi.render :allow_put
      _(response[:success]).must_equal true
    end

    it 'stores PUT method for allow: :put' do
      opts = RestfulDefineApi.opts
      _(opts[:collection][:allow_put][:allow]).must_equal ['PUT']
    end
  end

  describe 'multiple HTTP methods for same action' do
    it 'works with [:get, :put] => :action' do
      response = RestfulDefineApi.render :multi_method
      _(response[:success]).must_equal true
      _(response[:data]).must_equal 'multi_method_result'
    end

    it 'stores multiple methods for [:get, :put] => :action' do
      opts = RestfulDefineApi.opts
      _(opts[:collection][:multi_method][:allow]).must_equal ['GET', 'PUT']
    end

    it 'works with allow: [:get, :delete]' do
      response = RestfulDefineApi.render :multi_allow
      _(response[:success]).must_equal true
      _(response[:data]).must_equal 'multi_allow_result'
    end

    it 'stores multiple methods for allow: [:get, :delete]' do
      opts = RestfulDefineApi.opts
      _(opts[:collection][:multi_allow][:allow]).must_equal ['GET', 'DELETE']
    end
  end

  describe 'member RESTful define' do
    it 'works with member get: :action' do
      response = RestfulDefineApi.render :member_rest_get, id: 42
      _(response[:success]).must_equal true
      _(response[:data]).must_equal 'member_42'
    end

    it 'stores GET for member get: :action' do
      opts = RestfulDefineApi.opts
      _(opts[:member][:member_rest_get][:allow]).must_equal ['GET']
    end

    it 'works with member allow: :get' do
      response = RestfulDefineApi.render :member_allow_get, id: 99
      _(response[:success]).must_equal true
      _(response[:data]).must_equal 'member_allow_99'
    end

    it 'stores GET for member allow: :get' do
      opts = RestfulDefineApi.opts
      _(opts[:member][:member_allow_get][:allow]).must_equal ['GET']
    end

    it 'works with member [:get, :put, :delete] => :action' do
      response = RestfulDefineApi.render :member_multi, id: 77
      _(response[:success]).must_equal true
      _(response[:data]).must_equal 'member_multi_77'
    end

    it 'stores multiple methods for member' do
      opts = RestfulDefineApi.opts
      _(opts[:member][:member_multi][:allow]).must_equal ['GET', 'PUT', 'DELETE']
    end
  end
end
