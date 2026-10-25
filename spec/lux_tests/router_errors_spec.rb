require 'test_helper'

class ErrorsNoHandlerRouter < Lux::Router
  def show = raise('plain boom')
  def missing = raise(Lux.error.not_found('no such thing'))
end

class ErrorsRaisingHandlerRouter < Lux::Router
  rescue_from { |_err| raise 'handler broke' }

  def show = raise('first')
end

class ErrorsSilentHandlerRouter < Lux::Router
  rescue_from { |err| lux.var[:seen] = err.message }

  def show = raise('silent boom')
end

class ErrorsTemplateRouter < Lux::Router
  template_root './spec/fixtures/views'
  views :errors
  layout false

  rescue_from { |err| render text: "caught:#{err.class}" }

  def show; end
end

ERRORS_SPEC_ROUTE ||= proc do
  map 'errors' do
    map 'none',     'errors_no_handler#show'
    map 'missing',  'errors_no_handler#missing'
    map 'raising',  'errors_raising_handler#show'
    map 'silent',   'errors_silent_handler#show'
    map 'template', 'errors_template#show'
  end
end

describe 'Lux::Router error handling' do
  before do
    Lux.router.route(&ERRORS_SPEC_ROUTE)
    # other specs register a root rescue_from; these cases need it gone
    @root_handlers = Lux::Router.instance_variable_get(:@rescue_handlers)
    Lux::Router.instance_variable_set(:@rescue_handlers, nil)
    @prev_debug = Lux.debug?
  end

  after do
    Lux::Router.instance_variable_set(:@rescue_handlers, @root_handlers)
    Lux.debug = @prev_debug
  end

  describe 'no rescue_from' do
    it 'renders the default error screen with the error status' do
      res = Lux.render.get('/errors/missing')
      assert_status 404, res
      assert_body_includes 'no such thing', res
      assert_body_includes '<!DOCTYPE html>', res
    end

    it 'answers JSON requests with a JSON error' do
      res = Lux.render.get('/errors/none', headers: { 'Content-Type' => 'application/json' })
      assert_status 500, res
      assert_json_includes({ status: 500, error: 'plain boom' }, res)
    end
  end

  it 'falls back to the default screen when the handler renders nothing' do
    res = Lux.render.get('/errors/silent')
    assert_status 500, res
    assert_body_includes 'silent boom', res
  end

  it 'routes a template exception through rescue_from' do
    res = Lux.render.get('/errors/template')
    assert_status 500, res
    assert_equal 'caught:NameError', res.body
  end

  describe 'handler raises' do
    it 'dumps the second error in debug' do
      Lux.debug = true
      res = Lux.render.get('/errors/raising')
      assert_status 500, res
      assert_body_includes 'handler broke', res
      assert_body_includes 'Backtrace', res
    end

    it 'hides the message outside debug' do
      Lux.debug = false
      res = Lux.render.get('/errors/raising')
      assert_status 500, res
      assert_body_includes 'Internal Server Error', res
      refute_includes res.body, 'handler broke'
    end
  end
end
