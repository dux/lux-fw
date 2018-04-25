require 'spec_helper'

Lux.app.routes do
  map :plain => lambda { current.response.body 'plain' }
  map '/@'   => [RoutesTestCell, :user]
  map %r{~}  => RoutesTestCell

  map '/test1/test2/:foo' => 'routes_test#foo'

  response.body = 'not found'
  response.status 404
end

describe Lux::Application do
  it 'should get right routess' do
    expect(Lux.app.render('/plain').body).to eq 'plain'
    expect(Lux.app.render('/@dux').body).to  eq 'user'
    expect(Lux.app.render('/~dux').body).to  eq 'tilda'
  end

  it 'should get nested routess' do
    expect(Lux.app.render('/test1/test2/bar').body).to eq 'bar'
  end

  it 'should get bad routes' do
    expect(Lux.app.render('/not-found').status).to eq 404
    expect(Lux.app.render('/x@dux').status).to eq 404
  end
end

###

class RoutesTestCell < Lux::Cell
  def index
    render text: 'tilda'
  end

  def user
    render text: 'user'
  end

  def foo
    render text: params[:foo]
  end
end
