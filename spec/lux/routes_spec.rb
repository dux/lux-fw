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

class Lux::Application
  def main
    get :plain => lambda { current.response.body 'plain' }
    get '/@'   => [RoutesTestCell, :user]
    get %r{~}  => RoutesTestCell
  end
end

describe Lux::Application do
  it 'should get right routess' do
    expect(Lux('/plain').body).to eq 'plain'
    expect(Lux('/@dux').body).to  eq 'user'
    expect(Lux('/~dux').body).to  eq 'tilda'

    expect(Lux('/not-found').status).to eq 500
    expect(Lux('/x@dux').status).to eq 500
  end
end