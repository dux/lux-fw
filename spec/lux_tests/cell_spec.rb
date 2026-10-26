require 'test_helper'

class TestRouter < Lux::Router
  before do
    @before = 'before'
  end

  before do
    @second = 'second'
  end

  before_render do
    @before_render = 'before_render'
  end

  ###

  def render_text
    render text: 'foo'
  end

  def render_json
    render json: { foo: 'bar' }
  end

  def render_fail
    render foo: 'bar'
  end

  def test_before
    render text: @before + @second
  end

  def test_before_render_value
    # before_render only fires in template rendering path, not static renders.
    # Verify the callback is registered and fires when invoked.
    run_callback :before_render, :test_before_render_value
    render text: @before_render.to_s
  end
end

###

describe Lux::Router do
  before do
    Lux::Context.new('http://testing')
  end

  it 'renders text' do
    TestRouter.action(:render_text)

    _(Lux.ctx.response.body).must_equal 'foo'
  end

  it 'renders json' do
    TestRouter.action(:render_json)

    _(Lux.ctx.response.body).must_equal '{"foo":"bar"}'
  end

  it 'raises on invalid render options' do
    _{ TestRouter.action(:render_fail) }.must_raise ArgumentError
  end

  it 'executes before filters in order' do
    TestRouter.action(:test_before)

    _(Lux.ctx.response.body).must_equal 'beforesecond'
  end

  it 'executes before_render callback when invoked' do
    TestRouter.action(:test_before_render_value)

    _(Lux.ctx.response.body).must_equal 'before_render'
  end
end
