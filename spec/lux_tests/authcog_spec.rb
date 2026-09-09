require 'test_helper'
require_relative '../../plugins/authcog/load/authcog_controller'

describe AuthcogController do
  # what a view renders: a plain local path, so a link drawn into a shared layout
  # or a cached page carries no per-browser secret
  it 'links to its own mount path' do
    _(AuthcogController.auth_link).must_equal '/authcog'
  end

  it 'builds the exchange base with the development port' do
    url = Lux::Utils::Url.new('http://lvh.me:3000/authcog')

    _(AuthcogController.exchange_base(url))
      .must_equal 'https://auth.authcog.com/domain:lvh.me/port:3000'
  end

  it 'builds the exchange base without a production default port' do
    url = Lux::Utils::Url.new('https://izlazni.com/authcog')

    _(AuthcogController.exchange_base(url))
      .must_equal 'https://auth.authcog.com/domain:izlazni.com'
  end

  it 'omits the default http port' do
    url = Lux::Utils::Url.new('http://lvh.me:80/authcog')

    _(AuthcogController.exchange_base(url))
      .must_equal 'https://auth.authcog.com/domain:lvh.me'
  end
end
