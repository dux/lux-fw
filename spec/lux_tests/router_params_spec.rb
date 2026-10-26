require 'test_helper'

# A router with no params declarations - loose, current.params passes through.
class LooseParamsRouter < Lux::Router
  def show
    render text: Lux.ctx.params.to_h.to_json
  end
end

# Method-level opt only.
class MethodOptRouter < Lux::Router
  opt :name,  String, max: 30
  opt :age?,  Integer
  def create
    render text: Lux.ctx.params.to_h.to_json
  end

  def index
    render text: Lux.ctx.params.to_h.to_json
  end
end

# Class-level params block only.
class ClassParamsRouter < Lux::Router
  params do
    org_id   :string
    api_key? :string
  end

  def show
    render text: Lux.ctx.params.to_h.to_json
  end
end

# Both class-level and method-level - method wins on collision.
class CombinedParamsRouter < Lux::Router
  params do
    org_id   :string
    api_key? :string
  end

  opt :name,   String
  opt :org_id, :string, req: false   # method override: optional
  def update
    render text: Lux.ctx.params.to_h.to_json
  end
end

# Shortcut DSL inside params block: `foo Integer, max: 100` ==
# `set :foo, type: Integer, max: 100`. Same parser as Lux::Schema::Define.
class ShortcutFormRouter < Lux::Router
  params do
    age Integer, max: 100
    tag? type: :string
  end

  def show
    render text: Lux.ctx.params.to_h.to_json
  end
end

###

describe 'Lux::Router opt / params DSL' do
  before do
    Lux::Context.new('http://test')
  end

  describe 'no declarations (loose)' do
    it 'passes params through untouched' do
      Lux::Context.new('http://test/show', query_string: { foo: 'bar', baz: 'qux' })
      LooseParamsRouter.action(:show)
      body = JSON.parse(Lux.ctx.response.body)
      _(body).must_equal('foo' => 'bar', 'baz' => 'qux')
    end
  end

  describe 'method-level opt only' do
    it 'keeps only declared keys and coerces types' do
      Lux::Context.new('http://test/create', query_string: { 'name' => 'Dux', 'age' => '42', 'extra' => 'drop' })
      MethodOptRouter.action(:create)
      body = JSON.parse(Lux.ctx.response.body)
      _(body).must_equal('name' => 'Dux', 'age' => 42)
    end

    it 'lets undeclared actions remain loose' do
      Lux::Context.new('http://test/index', query_string: { whatever: 'goes' })
      MethodOptRouter.action(:index)
      body = JSON.parse(Lux.ctx.response.body)
      _(body).must_equal('whatever' => 'goes')
    end

    it 'returns 422 on missing required keys for JSON requests' do
      Lux::Context.new('http://test/create.json', query_string: { 'age' => '42' })
      MethodOptRouter.action(:create)
      _(Lux.ctx.response.status).must_equal 422
      body = JSON.parse(Lux.ctx.response.body)
      _(body['errors']).must_include 'name'
    end
  end

  describe 'class-level params block only' do
    it 'applies to every action' do
      Lux::Context.new('http://test/show', query_string: { 'org_id' => 'abc', 'api_key' => 'xyz', 'extra' => 'drop' })
      ClassParamsRouter.action(:show)
      body = JSON.parse(Lux.ctx.response.body)
      _(body).must_equal('org_id' => 'abc', 'api_key' => 'xyz')
    end
  end

  describe 'class-level + method-level (method wins)' do
    it 'unions allowed keys and uses method-level options for collisions' do
      # org_id is required at class-level but optional at method-level; method should win
      Lux::Context.new('http://test/update.json', query_string: { 'name' => 'Dux', 'extra' => 'drop' })
      CombinedParamsRouter.action(:update)
      _(Lux.ctx.response.status).wont_equal 422
      body = JSON.parse(Lux.ctx.response.body)
      _(body).must_equal('name' => 'Dux', 'org_id' => nil, 'api_key' => nil)
    end
  end

  describe 'shortcut form inside params block' do
    it 'parses `field Type, max:` identically to set' do
      Lux::Context.new('http://test/show', query_string: { 'age' => '15', 'tag' => 'hi', 'extra' => 'drop' })
      ShortcutFormRouter.action(:show)
      body = JSON.parse(Lux.ctx.response.body)
      _(body).must_equal('age' => 15, 'tag' => 'hi')
    end
  end
end
