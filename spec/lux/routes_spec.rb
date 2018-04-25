require 'spec_helper'

class RoutesTestCell < Lux::Cell
  def call
    return action(current.nav.root) if current.nav.root && respond_to?(current.nav.root)

    render text: 'tilda'
  end

  def user
    render text: 'user'
  end
end

Lux.app.routes do
  map :plain => lambda { current.response.body 'plain' }
  map '/@'   => [RoutesTestCell, :user]
  map %r{~}  => RoutesTestCell

  response.body = 'not found'
  response.status 404
end

describe Lux::Application do
  it 'should get right routess' do
    expect(Lux.app.render('/plain').body).to eq 'plain'
    expect(Lux.app.render('/@dux').body).to  eq 'user'
    expect(Lux.app.render('/~dux').body).to  eq 'tilda'

    expect(Lux.app.render('/not-found').status).to eq 404
    expect(Lux.app.render('/x@dux').status).to eq 404
  end
end