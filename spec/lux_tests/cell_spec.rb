require 'spec_helper'

class TestController < Lux::Controller
  before do
    @before = 'before'
  end

  before_action do
    @before_action = 'before_action'
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
    render text: @before + @before_action
  end

  def test_before_render_value
    # before_render only fires in template rendering path, not static renders.
    # Verify the callback is registered and fires when invoked.
    run_callback :before_render, :test_before_render_value
    render text: @before_render.to_s
  end
end

###

describe Lux::Controller do
  before do
    Lux::Current.new('http://testing')
  end

  it 'renders text' do
    TestController.action(:render_text)

    expect(Lux.current.response.body).to eq('foo')
  end

  it 'renders json' do
    TestController.action(:render_json)

    expect(Lux.current.response.body).to eq({ foo: 'bar' })
  end

  it 'renders failure with 500 status' do
    TestController.action(:render_fail)

    expect(Lux.current.response.status).to eq(500)
  end

  it 'executes before and before_action filters' do
    TestController.action(:test_before)

    expect(Lux.current.response.body).to eq('beforebefore_action')
  end

  it 'executes before_render callback when invoked' do
    TestController.action(:test_before_render_value)

    expect(Lux.current.response.body).to eq('before_render')
  end
end


