require 'spec_helper'

# A controller with no params declarations - loose, current.params passes through.
class LooseParamsController < Lux::Controller
  def show
    render text: lux.params.to_h.to_json
  end
end

# Method-level opt only.
class MethodOptController < Lux::Controller
  opt :name,  String, max: 30
  opt :age?,  Integer
  def create
    render text: lux.params.to_h.to_json
  end

  def index
    render text: lux.params.to_h.to_json
  end
end

# Class-level params block only.
class ClassParamsController < Lux::Controller
  params do
    org_id   :string
    api_key? :string
  end

  def show
    render text: lux.params.to_h.to_json
  end
end

# Both class-level and method-level - method wins on collision.
class CombinedParamsController < Lux::Controller
  params do
    org_id   :string
    api_key? :string
  end

  opt :name,   String
  opt :org_id, :string, req: false   # method override: optional
  def update
    render text: lux.params.to_h.to_json
  end
end

# Shortcut DSL inside params block: `foo Integer, max: 100` ==
# `set :foo, type: Integer, max: 100`. Same parser as Lux::Schema::Define.
class ShortcutFormController < Lux::Controller
  params do
    age Integer, max: 100
    tag? type: :string
  end

  def show
    render text: lux.params.to_h.to_json
  end
end

###

describe 'Lux::Controller opt / params DSL' do
  before do
    Lux::Current.new('http://test')
  end

  describe 'no declarations (loose)' do
    it 'passes params through untouched' do
      Lux::Current.new('http://test/show', query_string: { foo: 'bar', baz: 'qux' })
      LooseParamsController.action(:show)
      body = JSON.parse(Lux.current.response.body)
      expect(body).to eq('foo' => 'bar', 'baz' => 'qux')
    end
  end

  describe 'method-level opt only' do
    it 'keeps only declared keys and coerces types' do
      Lux::Current.new('http://test/create', query_string: { 'name' => 'Dux', 'age' => '42', 'extra' => 'drop' })
      MethodOptController.action(:create)
      body = JSON.parse(Lux.current.response.body)
      expect(body).to eq('name' => 'Dux', 'age' => 42)
    end

    it 'lets undeclared actions remain loose' do
      Lux::Current.new('http://test/index', query_string: { whatever: 'goes' })
      MethodOptController.action(:index)
      body = JSON.parse(Lux.current.response.body)
      expect(body).to eq('whatever' => 'goes')
    end

    it 'returns 422 on missing required keys for JSON requests' do
      Lux::Current.new('http://test/create.json', query_string: { 'age' => '42' })
      MethodOptController.action(:create)
      expect(Lux.current.response.status).to eq(422)
      body = JSON.parse(Lux.current.response.body)
      expect(body['errors']).to have_key('name')
    end
  end

  describe 'class-level params block only' do
    it 'applies to every action' do
      Lux::Current.new('http://test/show', query_string: { 'org_id' => 'abc', 'api_key' => 'xyz', 'extra' => 'drop' })
      ClassParamsController.action(:show)
      body = JSON.parse(Lux.current.response.body)
      expect(body).to eq('org_id' => 'abc', 'api_key' => 'xyz')
    end
  end

  describe 'class-level + method-level (method wins)' do
    it 'unions allowed keys and uses method-level options for collisions' do
      # org_id is required at class-level but optional at method-level; method should win
      Lux::Current.new('http://test/update.json', query_string: { 'name' => 'Dux', 'extra' => 'drop' })
      CombinedParamsController.action(:update)
      expect(Lux.current.response.status).not_to eq(422)
      body = JSON.parse(Lux.current.response.body)
      expect(body).to eq('name' => 'Dux', 'org_id' => nil, 'api_key' => nil)
    end
  end

  describe 'shortcut form inside params block' do
    it 'parses `field Type, max:` identically to set' do
      Lux::Current.new('http://test/show', query_string: { 'age' => '15', 'tag' => 'hi', 'extra' => 'drop' })
      ShortcutFormController.action(:show)
      body = JSON.parse(Lux.current.response.body)
      expect(body).to eq('age' => 15, 'tag' => 'hi')
    end
  end
end
