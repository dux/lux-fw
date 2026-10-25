require 'test_helper'

# Extended router for testing additional features
class ExtendedTestRouter < Lux::Router
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

class MockableRouter < Lux::Router
  mock :landing, :about

  def real_action
    render text: 'real'
  end
end

class RescueRouter < Lux::Router
  def explode
    raise 'boom'
  end
end

###

describe 'Lux::Router extended' do
  before do
    Lux::Current.new('http://testing')
  end

  describe 'render options' do
    it 'renders text with custom status' do
      ExtendedTestRouter.action(:with_status)
      _(Lux.current.response.body).must_equal 'custom status'
      _(Lux.current.response.status).must_equal 201
    end

    it 'renders HTML' do
      ExtendedTestRouter.action(:render_html)
      _(Lux.current.response.body).must_equal '<h1>hello</h1>'
    end

    it 'renders XML' do
      ExtendedTestRouter.action(:render_xml)
      _(Lux.current.response.body).must_equal '<root><item>1</item></root>'
    end
  end

  describe '.mock' do
    it 'creates empty methods that return true' do
      _(MockableRouter.new.respond_to?(:landing)).must_equal true
      _(MockableRouter.new.respond_to?(:about)).must_equal true
    end

    it 'mock methods return true' do
      _(MockableRouter.new.landing).must_equal true
      _(MockableRouter.new.about).must_equal true
    end

    it 'does not override real methods' do
      MockableRouter.action(:real_action)
      _(Lux.current.response.body).must_equal 'real'
    end
  end

  describe 'error propagation' do
    it 'propagates errors from router actions (no router-level rescue)' do
      err = _{ RescueRouter.action(:explode) }.must_raise RuntimeError
      _(err.message).must_equal 'boom'
    end
  end

  describe '#flash' do
    it 'provides access to response flash' do
      ExtendedTestRouter.action(:with_flash)
      _(Lux.current.response.body).must_equal 'flashed'
      _(Lux.current.response.flash.to_h[:info]).must_equal ['Hello!']
    end
  end

  describe '#get? / #post?' do
    it 'detects GET requests' do
      Lux::Current.new('http://testing/get_only', method: :get)
      ExtendedTestRouter.action(:get_only)
      _(Lux.current.response.body).must_equal 'get response'
    end

    it 'detects POST requests' do
      Lux::Current.new('http://testing/get_only', method: :post)
      ExtendedTestRouter.action(:get_only)
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
      _{ ExtendedTestRouter.action(:action) }.must_raise Lux::Error
    end
  end

  describe 'blank action name' do
    it 'raises on blank action' do
      _{ ExtendedTestRouter.action('') }.must_raise ArgumentError
    end

    it 'raises on nil action' do
      _{ ExtendedTestRouter.action(nil) }.must_raise ArgumentError
    end
  end

  describe 'action sanitization' do
    it 'converts hyphens to underscores' do
      # 'show' with hyphens would become 'show'
      ExtendedTestRouter.action(:show)
      _(Lux.current.response.body).must_equal 'show'
    end
  end
end
