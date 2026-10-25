require 'test_helper'

class ErrorPageTestRouter < Lux::Router
  before { lux.var[:before_ran] = true }

  def error
    render text: 'error page'
  end
end

describe 'error page dispatch' do
  before do
    Lux::Current.new('http://test.example.com/')
  end

  it 'skips the before pipeline when Router#render_error dispatches' do
    lux.var[:error_page] = true
    ErrorPageTestRouter.action(:error)

    assert_nil lux.var[:before_ran]
    _(lux.response.body).must_equal 'error page'
  end

  it 'runs before filters for a regular dispatch of the same action' do
    ErrorPageTestRouter.action(:error)
    _(lux.var[:before_ran]).must_equal true
  end
end
