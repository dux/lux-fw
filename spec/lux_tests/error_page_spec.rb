require 'test_helper'

class ErrorPageTestRouter < Lux::Router
  before { Lux.ctx.var[:before_ran] = true }

  def error
    render text: 'error page'
  end
end

describe 'error page dispatch' do
  before do
    Lux::Context.new('http://test.example.com/')
  end

  it 'skips the before pipeline when Router#render_error dispatches' do
    Lux.ctx.var[:error_page] = true
    ErrorPageTestRouter.action(:error)

    assert_nil Lux.ctx.var[:before_ran]
    _(Lux.ctx.response.body).must_equal 'error page'
  end

  it 'runs before filters for a regular dispatch of the same action' do
    ErrorPageTestRouter.action(:error)
    _(Lux.ctx.var[:before_ran]).must_equal true
  end
end
