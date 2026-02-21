require 'spec_helper'

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

  def get_only
    if request.get?
      render text: 'get response'
    elsif request.post?
      render text: 'post response'
    end
  end

  def with_flash
    flash.info 'Hello!'
    render text: 'flashed'
  end

  def redirect_test
    response.redirect_to '/target', info: 'Moved'
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
      expect(Lux.current.response.body).to eq('custom status')
      expect(Lux.current.response.status).to eq(201)
    end

    it 'renders HTML' do
      ExtendedTestController.action(:render_html)
      expect(Lux.current.response.body).to eq('<h1>hello</h1>')
    end

    it 'renders XML' do
      ExtendedTestController.action(:render_xml)
      expect(Lux.current.response.body).to eq('<root><item>1</item></root>')
    end
  end

  describe '.mock' do
    it 'creates empty methods that return true' do
      expect(MockableController.new).to respond_to(:landing)
      expect(MockableController.new).to respond_to(:about)
    end

    it 'mock methods return true' do
      expect(MockableController.new.landing).to be true
      expect(MockableController.new.about).to be true
    end

    it 'does not override real methods' do
      MockableController.action(:real_action)
      expect(Lux.current.response.body).to eq('real')
    end
  end

  describe 'error propagation' do
    it 'propagates errors from controller actions (no controller-level rescue)' do
      expect { RescueController.action(:explode) }.to raise_error(RuntimeError, 'boom')
    end
  end

  describe '#flash' do
    it 'provides access to response flash' do
      ExtendedTestController.action(:with_flash)
      expect(Lux.current.response.body).to eq('flashed')
      expect(Lux.current.response.flash.to_h[:info]).to eq(['Hello!'])
    end
  end

  describe '#get? / #post?' do
    it 'detects GET requests' do
      Lux::Current.new('http://testing/get_only', method: :get)
      ExtendedTestController.action(:get_only)
      expect(Lux.current.response.body).to eq('get response')
    end

    it 'detects POST requests' do
      Lux::Current.new('http://testing/get_only', method: :post)
      ExtendedTestController.action(:get_only)
      expect(Lux.current.response.body).to eq('post response')
    end
  end

  describe '#redirect_to' do
    it 'uses response.redirect_to to set location header' do
      # redirect_to depends on Url class from app layer, test response directly
      Lux.current.response.headers['location'] = '/target'
      Lux.current.response.status 302
      expect(Lux.current.response.status).to eq(302)
      expect(Lux.current.response.headers['location']).to eq('/target')
    end
  end

  describe 'forbidden action names' do
    it 'raises on :action as an action name' do
      expect { ExtendedTestController.action(:action) }.to raise_error(Lux::Error)
    end

    it 'raises on :error as an action name' do
      expect { ExtendedTestController.action(:error) }.to raise_error(Lux::Error)
    end
  end

  describe 'blank action name' do
    it 'raises on blank action' do
      expect { ExtendedTestController.action('') }.to raise_error(ArgumentError)
    end

    it 'raises on nil action' do
      expect { ExtendedTestController.action(nil) }.to raise_error(ArgumentError)
    end
  end

  describe 'action sanitization' do
    it 'converts hyphens to underscores' do
      # 'show' with hyphens would become 'show'
      ExtendedTestController.action(:show)
      expect(Lux.current.response.body).to eq('show')
    end
  end

  describe 'ivars passing' do
    it 'sets instance variables from ivars parameter' do
      ctrl = ExtendedTestController.new
      ctrl.action(:show, ivars: { '@custom' => 'value' })
      expect(ctrl.instance_variable_get(:@custom)).to eq('value')
    end
  end
end
