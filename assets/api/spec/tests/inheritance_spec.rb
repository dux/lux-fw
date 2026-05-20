require_relative '../loader'

describe 'inheritance and super!' do
  context 'method inheritance' do
    it 'inherits methods from parent class' do
      # UserApi inherits from ModelApi which has member :creator
      response = UserApi.render :creator, id: 1, params: { show_all: false }
      expect(response[:success]).to eq(true)
      expect(response[:data]).to eq('@dux')
    end

    it 'inherits collection methods' do
      # UserApi collection :call_me_in_child overrides ModelApi
      # but still inherits the base implementation
      response = UserApi.render :call_me_in_child
      expect(response[:success]).to eq(true)
      expect(response[:data]).to eq(4690)  # 2345 * 2
    end

    it 'inherits member methods' do
      response = UserApi.render :call_me_in_child, id: 1
      expect(response[:success]).to eq(true)
      expect(response[:data]).to eq(2468)  # 1234 * 2
    end
  end

  context 'super! method' do
    it 'calls parent implementation via super!' do
      # UserApi collection :call_me_in_child calls super! * 2
      # ModelApi :call_me_in_child sets @number = 2345
      response = UserApi.render :call_me_in_child
      expect(response[:data]).to eq(4690)  # 2345 * 2
    end

    it 'calls parent member method via super!' do
      # UserApi member :call_me_in_child calls super! and then @number * 2
      # ModelApi member :call_me_in_child sets @number = 1234
      response = UserApi.render :call_me_in_child, id: 1
      expect(response[:data]).to eq(2468)  # 1234 * 2
    end
  end

  context 'opts inheritance' do
    it 'inherits method options from ancestors' do
      # CompanyApi inherits from ModelApi which has :creator method
      opts = CompanyApi.opts
      expect(opts[:member][:creator]).not_to be_nil
      expect(opts[:member][:creator][:desc]).to be_truthy  # has some description
    end

    it 'child can override parent method options' do
      # Check that child opts take precedence
      child_opts = UserApi.opts
      parent_opts = ModelApi.opts

      # Both should have call_me_in_child but with different allow values
      expect(child_opts[:collection][:call_me_in_child][:allow]).to eq(['DELETE'])
    end
  end

  context 'callback inheritance' do
    it 'inherits before callbacks from ancestors' do
      # ApplicationApi before sets @_time
      # This should run for all descendants
      response = CompanyApi.render :show, id: 1
      expect(response[:success]).to eq(true)
    end

    it 'inherits after callbacks from ancestors' do
      # ApplicationApi after sets :ip meta
      response = CompanyApi.render :show, id: 1
      expect(response[:meta][:ip]).to eq('1.2.3.4')
    end
  end

  context 'module inclusion' do
    it 'includes methods from classic module' do
      response = GenericApi.render :module_clasic
      expect(response[:success]).to eq(true)
      expect(response[:data]).to eq('is_module')
    end
  end

  context 'plugin inheritance' do
    it 'includes methods from plugin' do
      response = GenericApi.render :plugin_test
      expect(response[:success]).to eq(true)
      expect(response[:data]).to eq('from_plugin')
    end
  end
end
