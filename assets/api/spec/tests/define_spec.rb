require_relative '../loader'

describe 'define block syntax' do
  before(:all) do
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

  it 'works with simple define block' do
    response = DefineTestApi.render :simple_define
    expect(response[:success]).to eq(true)
    expect(response[:data]).to eq('simple')
  end

  it 'works with params in define block' do
    response = DefineTestApi.render :with_params, params: { name: 'John', age: 30 }
    expect(response[:success]).to eq(true)
    expect(response[:data][:name]).to eq('John')
    expect(response[:data][:age]).to eq(30)
  end

  it 'validates required params in define block' do
    response = DefineTestApi.render :with_params, params: { age: 30 }
    expect(response[:success]).to eq(false)
  end

  it 'stores desc and detail from define block' do
    opts = DefineTestApi.opts
    expect(opts[:collection][:with_desc][:desc]).to eq('A described method')
    expect(opts[:collection][:with_desc][:detail]).to eq('More details here')
  end

  it 'works with unsafe annotation in define block' do
    opts = DefineTestApi.opts
    expect(opts[:collection][:with_annotations][:unsafe]).to eq(true)
  end

  it 'works with member define block' do
    response = DefineTestApi.render :member_define, id: 123
    expect(response[:success]).to eq(true)
    expect(response[:data]).to eq('member_123')
  end

  it 'stores allow from define block' do
    opts = DefineTestApi.opts
    expect(opts[:member][:with_allow][:allow]).to eq(['GET'])
  end

  it 'stores multiple allows from allow :get, :put' do
    opts = DefineTestApi.opts
    expect(opts[:member][:with_multi_allow][:allow]).to eq(['GET', 'PUT'])
  end

  it 'existing define in CompanyApi works' do
    response = CompanyApi.render.foo(1, bar: 5)
    expect(response[:data]).to eq(15)
  end
end

describe 'RESTful define syntax' do
  before(:all) do
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

  context 'define http: :action syntax' do
    it 'works with get: :action' do
      response = RestfulDefineApi.render :rest_get
      expect(response[:success]).to eq(true)
      expect(response[:data]).to eq('rest_get_result')
    end

    it 'stores GET method for get: :action' do
      opts = RestfulDefineApi.opts
      expect(opts[:collection][:rest_get][:allow]).to eq(['GET'])
    end

    it 'works with post: :action' do
      response = RestfulDefineApi.render :rest_post
      expect(response[:success]).to eq(true)
      expect(response[:data]).to eq('rest_post_result')
    end

    it 'stores POST method for post: :action' do
      opts = RestfulDefineApi.opts
      expect(opts[:collection][:rest_post][:allow]).to eq(['POST'])
    end

    it 'works with put: :action' do
      response = RestfulDefineApi.render :rest_put
      expect(response[:success]).to eq(true)
    end

    it 'stores PUT method for put: :action' do
      opts = RestfulDefineApi.opts
      expect(opts[:collection][:rest_put][:allow]).to eq(['PUT'])
    end

    it 'works with delete: :action' do
      response = RestfulDefineApi.render :rest_delete
      expect(response[:success]).to eq(true)
    end

    it 'stores DELETE method for delete: :action' do
      opts = RestfulDefineApi.opts
      expect(opts[:collection][:rest_delete][:allow]).to eq(['DELETE'])
    end
  end

  context 'define :action, allow: :method syntax' do
    it 'works with allow: :get' do
      response = RestfulDefineApi.render :allow_get
      expect(response[:success]).to eq(true)
      expect(response[:data]).to eq('allow_get_result')
    end

    it 'stores GET method for allow: :get' do
      opts = RestfulDefineApi.opts
      expect(opts[:collection][:allow_get][:allow]).to eq(['GET'])
    end

    it 'works with allow: :put' do
      response = RestfulDefineApi.render :allow_put
      expect(response[:success]).to eq(true)
    end

    it 'stores PUT method for allow: :put' do
      opts = RestfulDefineApi.opts
      expect(opts[:collection][:allow_put][:allow]).to eq(['PUT'])
    end
  end

  context 'multiple HTTP methods for same action' do
    it 'works with [:get, :put] => :action' do
      response = RestfulDefineApi.render :multi_method
      expect(response[:success]).to eq(true)
      expect(response[:data]).to eq('multi_method_result')
    end

    it 'stores multiple methods for [:get, :put] => :action' do
      opts = RestfulDefineApi.opts
      expect(opts[:collection][:multi_method][:allow]).to eq(['GET', 'PUT'])
    end

    it 'works with allow: [:get, :delete]' do
      response = RestfulDefineApi.render :multi_allow
      expect(response[:success]).to eq(true)
      expect(response[:data]).to eq('multi_allow_result')
    end

    it 'stores multiple methods for allow: [:get, :delete]' do
      opts = RestfulDefineApi.opts
      expect(opts[:collection][:multi_allow][:allow]).to eq(['GET', 'DELETE'])
    end
  end

  context 'member RESTful define' do
    it 'works with member get: :action' do
      response = RestfulDefineApi.render :member_rest_get, id: 42
      expect(response[:success]).to eq(true)
      expect(response[:data]).to eq('member_42')
    end

    it 'stores GET for member get: :action' do
      opts = RestfulDefineApi.opts
      expect(opts[:member][:member_rest_get][:allow]).to eq(['GET'])
    end

    it 'works with member allow: :get' do
      response = RestfulDefineApi.render :member_allow_get, id: 99
      expect(response[:success]).to eq(true)
      expect(response[:data]).to eq('member_allow_99')
    end

    it 'stores GET for member allow: :get' do
      opts = RestfulDefineApi.opts
      expect(opts[:member][:member_allow_get][:allow]).to eq(['GET'])
    end

    it 'works with member [:get, :put, :delete] => :action' do
      response = RestfulDefineApi.render :member_multi, id: 77
      expect(response[:success]).to eq(true)
      expect(response[:data]).to eq('member_multi_77')
    end

    it 'stores multiple methods for member' do
      opts = RestfulDefineApi.opts
      expect(opts[:member][:member_multi][:allow]).to eq(['GET', 'PUT', 'DELETE'])
    end
  end
end
