require 'test_helper'
require_relative '../../plugins/web_common/lib/authcog_controller'

describe AuthcogController do
  it 'builds auth link with development port' do
    url = Lux::Utils::Url.new('http://lvh.me:3000/authcog/login')

    _(AuthcogController.auth_link(url))
      .must_equal 'https://auth.authcog.com/domain:lvh.me/port:3000'
  end

  it 'builds auth link without production default port' do
    url = Lux::Utils::Url.new('https://izlazni.com/authcog/login')

    _(AuthcogController.auth_link(url))
      .must_equal 'https://auth.authcog.com/domain:izlazni.com'
  end

  it 'omits default http port' do
    url = Lux::Utils::Url.new('http://lvh.me:80/authcog/login')

    _(AuthcogController.auth_link(url))
      .must_equal 'https://auth.authcog.com/domain:lvh.me'
  end
end
