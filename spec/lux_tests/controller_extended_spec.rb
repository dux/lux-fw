require 'test_helper'

# Extended controller for testing additional features
class ExtendedTestController < Lux::Controller
  mock :mock_action

  before do
    @data = 'initialized'
  end

  def show
    render text: 'show'
  end

  def with_status
    render text: 'custom status', status: 201
  end

  def render_html
    render html: '<h1>hello</h1>'
  end

  def render_xml
    render xml: '<root><item>1</item></root>'
  end

  def forbidden_action_name
    action(:action) rescue render(text: 'caught')
  end

  allow :get, :post
  def get_only
    if lux.request.get?
      render text: 'get response'
    elsif lux.request.post?
      render text: 'post response'
    end
  end

  def with_flash
    flash.info 'Hello!'
    render text: 'flashed'
  end

  def redirect_test
    lux.response.redirect_to '/target', info: 'Moved'
  end
end

class MockableController < Lux::Controller
  mock :landing, :about

  def real_action
    render text: 'real'
  end
end

class RescueController < Lux::Controller
  def explode
    raise 'boom'
  end
end

###

describe 'Lux::Controller extended' do
  before do
    Lux::Current.new('http://testing')
  end

  describe 'render options' do
    it 'renders text with custom status' do
      ExtendedTestController.action(:with_status)
      _(Lux.current.response.body).must_equal 'custom status'
      _(Lux.current.response.status).must_equal 201
    end

    it 'renders HTML' do
      ExtendedTestController.action(:render_html)
      _(Lux.current.response.body).must_equal '<h1>hello</h1>'
    end

    it 'renders XML' do
      ExtendedTestController.action(:render_xml)
      _(Lux.current.response.body).must_equal '<root><item>1</item></root>'
    end
  end

  describe '.mock' do
    it 'creates empty methods that return true' do
      _(MockableController.new.respond_to?(:landing)).must_equal true
      _(MockableController.new.respond_to?(:about)).must_equal true
    end

    it 'mock methods return true' do
      _(MockableController.new.landing).must_equal true
      _(MockableController.new.about).must_equal true
    end

    it 'does not override real methods' do
      MockableController.action(:real_action)
      _(Lux.current.response.body).must_equal 'real'
    end
  end

  describe 'error propagation' do
    it 'propagates errors from controller actions (no controller-level rescue)' do
      err = _{ RescueController.action(:explode) }.must_raise RuntimeError
      _(err.message).must_equal 'boom'
    end
  end

  describe '#flash' do
    it 'provides access to response flash' do
      ExtendedTestController.action(:with_flash)
      _(Lux.current.response.body).must_equal 'flashed'
      _(Lux.current.response.flash.to_h[:info]).must_equal ['Hello!']
    end
  end

  describe '#get? / #post?' do
    it 'detects GET requests' do
      Lux::Current.new('http://testing/get_only', method: :get)
      ExtendedTestController.action(:get_only)
      _(Lux.current.response.body).must_equal 'get response'
    end

    it 'detects POST requests' do
      Lux::Current.new('http://testing/get_only', method: :post)
      ExtendedTestController.action(:get_only)
      _(Lux.current.response.body).must_equal 'post response'
    end
  end

  describe '#redirect_to' do
    it 'uses response.redirect_to to set location header' do
      # redirect_to depends on Url class from app layer, test response directly
      Lux.current.response.headers['location'] = '/target'
      Lux.current.response.status 302
      _(Lux.current.response.status).must_equal 302
      _(Lux.current.response.headers['location']).must_equal '/target'
    end
  end

  describe 'forbidden action names' do
    it 'raises on :action as an action name' do
      _{ ExtendedTestController.action(:action) }.must_raise Lux::Error
    end
  end

  describe 'default :error action' do
    it 'renders a self-contained HTML page with status and message' do
      err = Lux::Error.new('missing thing')
      ExtendedTestController.action(:error, ivars: { '@error' => err, '@status' => 404 })
      _(Lux.current.response.status).must_equal 404
      _(Lux.current.response.body).must_include '404'
      _(Lux.current.response.body).must_include 'Not Found'
      _(Lux.current.response.body).must_include 'missing thing'
      _(Lux.current.response.body).must_include '<!DOCTYPE html>'
    end

    it 'derives status from response.status when @status is not set' do
      Lux.current.response.status 422
      err = Lux::Error.new('unprocessable')
      ExtendedTestController.action(:error, ivars: { '@error' => err })
      _(Lux.current.response.status).must_equal 422
    end

    it 'defaults to 500 when neither @status nor response.status is set' do
      err = Lux::Error.new('boom')
      ExtendedTestController.action(:error, ivars: { '@error' => err })
      _(Lux.current.response.status).must_equal 500
    end

    it 'renders JSON when nav.format is json' do
      Lux::Current.new('http://testing/x.json')
      err = Lux::Error.new('boom')
      ExtendedTestController.action(:error, ivars: { '@error' => err, '@status' => 500 })
      _(Lux.current.response.body).must_include '"error"'
      _(Lux.current.response.body).must_include 'boom'
      _(Lux.current.response.body).must_include '500'
    end
  end

  describe 'blank action name' do
    it 'raises on blank action' do
      _{ ExtendedTestController.action('') }.must_raise ArgumentError
    end

    it 'raises on nil action' do
      _{ ExtendedTestController.action(nil) }.must_raise ArgumentError
    end
  end

  describe 'action sanitization' do
    it 'converts hyphens to underscores' do
      # 'show' with hyphens would become 'show'
      ExtendedTestController.action(:show)
      _(Lux.current.response.body).must_equal 'show'
    end
  end

  describe 'ivars passing' do
    it 'sets instance variables from ivars parameter' do
      ctrl = ExtendedTestController.new
      ctrl.action(:show, ivars: { '@custom' => 'value' })
      _(ctrl.instance_variable_get(:@custom)).must_equal 'value'
    end
  end

end
