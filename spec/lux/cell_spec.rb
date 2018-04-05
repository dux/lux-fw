require 'spec_helper'

class CellTestCell < Lux::Cell
  def before
    @before = 'before'
    super
  end

  before_action do
    @before_action = 'before_action'
  end

  before_render do
    @before_render = 'before_render'
  end

  ###

  def call
    root = current.nav.root

    raise @before        if root == 'call_test_before'
    raise @before_action if root == 'call_test_before_action'
    raise @before_render if root == 'call_test_before_render'

    action root
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
end

describe Lux::Cell do
  before do
    Lux::Current.new('http://testing')
  end

  it 'renders text' do
    CellTestCell.action(:render_text)
    expect(Lux.current.response.body).to eq('foo')
  end

  it 'renders json' do
    CellTestCell.action(:render_json)
    expect(Lux.current.response.body).to eq({ foo: 'bar' })
  end

  it 'renders fails' do
    expect{ CellTestCell.action(:render_fail)  }.to raise_error RuntimeError
  end

  it 'executes before filter' do
    CellTestCell.action(:test_before)
    expect(Lux.current.response.body).to eq('beforebefore_action')
  end

  it 'executes before_render filter' do
    CellTestCell.action(:test_before)
    expect(Lux.current.response.body).to eq('beforebefore_action')
  end

  it 'tests filters on call' do
    expect{
      Lux.app.render('/call_test_before') { CellTestCell.call }
    }.to raise_error(StandardError, 'before')

    expect{
      Lux.app.render('/call_test_before_action') { CellTestCell.call }
    }.to raise_error(StandardError, nil)

    expect{
      Lux.app.render('/call_test_before_render') { CellTestCell.call }
    }.to raise_error(StandardError, nil)
  end

end

