require 'spec_helper'

class ExplodingController < Lux::Controller
  def boom
    raise 'BOOM!'
  end

  def boom_via_call
    raise 'BOOM2'
  end
end

class AfterMutateController < Lux::Controller
  def show
    render text: 'hello'
  end
end

class AppRescueRenderController < Lux::Controller
  def show
    render text: 'APP-CATCH(%d): %s' % [@status, @error.message]
  end
end

class RoutesTestController < Lux::Controller
  def root
    render text: 'root'
  end

  def index
    render text: 'tilda'
  end

  def user
    render text: 'user'
  end

  def foo
    render text: lux.params[:foo]
  end

  def city
    render text: 'zagreb'
  end

  def nested
    respond_to(:js) do
      render json: { a: 1 }
    end

    render text: 'nested'
  end
end

###

Lux.app do
  after do
    if request.path == '/after-mutate'
      response.body { |b| b.gsub('hello', 'GREETINGS-FRIEND') }
    end
  end

  rescue_from do |err|
    if request.path == '/exploding-via-call'
      call 'app_rescue_render#show'
    else
      map 'app_rescue_render#show'
    end
  end

  routes do
    root 'routes_test#root'

    map :plain => proc { lux.response.body 'plain' }
    map %r{^@} => [RoutesTestController, :user]
    map %r{^~} => RoutesTestController

    map 'city' do
      root 'routes_test#city'
      map user: 'routes_test#user'
    end

    map [:array1, :array2] => 'routes_test#root'

    map '/test1/test2/:foo' => 'routes_test#foo'

    map 'zagreb' => 'routes_test#city'

    map 'routes_test' do
      map 'foo-nested' => 'routes_test#nested'
    end

    map 'exploding' => 'exploding#boom'
    map 'exploding-via-call' => 'exploding#boom_via_call'
    map 'after-mutate' => 'after_mutate#show'

    lux.response.body 'not found', status: 404
  end

  ###

  describe Lux::Application do
    it 'should get right routes' do
      expect(Lux.render.get('/').body).to  eq 'root'
      expect(Lux.render.get('/plain').body).to eq 'plain'
      expect(Lux.render.get('/@dux').body).to  eq 'user'
      expect(Lux.render.get('/~dux').body).to  eq 'tilda'
    end

    it 'should get nested routes' do
      expect(Lux.render.get('/test1/test2/bar').body).to eq 'bar'
      expect(Lux.render.get('/routes_test/foo-nested').body).to eq 'nested'
    end

    it 'should get list routes' do
      expect(Lux.render.get('/array1').body).to eq 'root'
      expect(Lux.render.get('/array2').body).to eq 'root'
    end

    it 'should get namespace routes' do
      expect(Lux.render.get('/zagreb').body).to eq 'zagreb'
      expect(Lux.render.get('/city').body).to eq 'zagreb'
      expect(Lux.render.get('/city/user').body).to eq 'user'
    end

    it 'should get bad routes' do
      expect(Lux.render.get('/not-found').status).to eq 404
      expect(Lux.render.get('/x@dux').status).to eq 404
    end

    it 'should render js route' do
      expect(Lux.render.get('/routes_test/foo-nested.js').body[:a]).to eq(1)
    end

    it 'dispatches errors through Application rescue_from when defined (always wins)' do
      res = Lux.render.get('/exploding')
      expect(res.status).to eq(500)
      expect(res.body).to eq('APP-CATCH(500): BOOM!')
    end

    it 'tolerates throw :done from `call` inside the rescue_from block' do
      # rescue_from in spec uses map; verify same-shape direct call also works
      res = Lux.render.get('/exploding-via-call')
      expect(res.status).to eq(500)
      expect(res.body).to eq('APP-CATCH(500): BOOM2')
    end

    it 'fires Application :after BEFORE headers, so content-length matches the mutated body' do
      res = Lux.render.get('/after-mutate')
      expect(res.body).to eq('GREETINGS-FRIEND')
      expect(res.headers['content-length']).to eq('GREETINGS-FRIEND'.bytesize.to_s)
    end
  end
end
