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
  def city_map
    nav.root == 'zagreb'
  end

  routes do
    root 'routes_test#root'

    map :plain => proc { response.body 'plain' }
    map %r{^@} => [RoutesTestController, :user]
    map %r{^~} => RoutesTestController

    map :city do
      root 'routes_test#city'
      map user: 'routes_test#user'
    end

    map [:array1, :array2] => 'routes_test#root'

    map '/test1/test2/:foo' => 'routes_test#foo'

    map 'routes_test' do
      map 'foo-nested' => 'routes_test#nested'
    end

    response.body 'not found', status: 404
  end

  ###

  describe Lux::Application do
    it 'should get right routes' do
      expect(Lux.app.new('/').info.body).to  eq 'root'
      expect(Lux.app.new('/plain').info.body).to eq 'plain'
      expect(Lux.app.new('/@dux').info.body).to  eq 'user'
      expect(Lux.app.new('/~dux').info.body).to  eq 'tilda'
    end

    it 'should get nested routes' do
      expect(Lux.app.new('/test1/test2/bar').info.body).to eq 'bar'
      expect(Lux.app.new('/routes_test/foo-nested').info.body).to eq 'nested'
    end

    it 'should get list routes' do
      expect(Lux.app.new('/array1').info.body).to eq 'root'
      expect(Lux.app.new('/array2').info.body).to eq 'root'
    end

    it 'should get namespace routes' do
      expect(Lux.app.new('/zagreb').info.body).to eq 'zagreb'
      expect(Lux.app.new('/zagreb/user').info.body).to eq 'user'
      expect(Lux.app.new('/zagreb/xxx').info.status).to eq 404
    end

    it 'should get bad routes' do
      expect(Lux.app.new('/not-found').info.status).to eq 404
      expect(Lux.app.new('/x@dux').info.status).to eq 404
    end

    it 'should render js route' do
      expect(Lux.app.new('/routes_test/foo-nested.js').info.body[:a]).to eq(1)
    end
  end
end
