require 'spec_helper'

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
    render text: params[:foo]
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
  namespace :city do
    nav.root == 'zagreb'
  end

  routes do
    root 'routes_test#root'

    map :plain => proc { response 'plain' }
    map %r{^@} => [RoutesTestController, :user]
    map %r{^~} => RoutesTestController

    namespace :city do
      root 'routes_test#city'
      map user: 'routes_test#user'
    end

    map [:array1, :array2] => 'routes_test#root'

    map '/test1/test2/:foo' => 'routes_test#foo'

    map 'routes_test' do
      map 'nested'
      map 'foo-nested' => :nested
    end

    response.status 404
    response.body 'not found'
  end

  ###

  describe Lux::Application do
    it 'should get right routess' do
      # expect(Lux.app.render('/').body).to      eq 'root'
      expect(Lux.app.render('/plain').body).to eq 'plain'
      # expect(Lux.app.render('/@dux').body).to  eq 'user'
      # expect(Lux.app.render('/~dux').body).to  eq 'tilda'
    end

    it 'should get nested routess' do
      expect(Lux.app.render('/test1/test2/bar').body).to eq 'bar'
      expect(Lux.app.render('/nested').body).to eq 'nested'
      expect(Lux.app.render('/foo-nested').body).to eq 'nested'
      expect(Lux.app.render('/foo-bar-nested').body).to eq 'not found'
    end

    it 'should get list routess' do
      expect(Lux.app.render('/array1').body).to eq 'root'
      expect(Lux.app.render('/array2').body).to eq 'root'
    end

    it 'should get namespace routess' do
      expect(Lux.app.render('/zagreb').body).to eq 'zagreb'
      expect(Lux.app.render('/zagreb/user').body).to eq 'user'
      expect{ Lux.app.render('/zagreb/xxx').body }.to raise_error(Lux::Error)
    end

    it 'should get bad routes' do
      expect(Lux.app.render('/not-found').status).to eq 404
      expect(Lux.app.render('/x@dux').status).to eq 404
    end

    it 'should render js route' do
      expect(Lux.app.render('/foo-nested.js').body).to eq({"a"=>1})
    end
  end
end
