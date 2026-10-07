require 'test_helper'

require_relative '../load/html/input/html_input'
require_relative '../load/html/input/html_input_custom'
require_relative '../load/html/form/html_form'
require_relative '../load/html/form/html_form_custom'

describe HtmlForm do
  # Lux::Test::Case clears Thread.current[:lux] after every test, so the stub cannot leak.
  before do
    request = Struct.new(:params).new({})
    Thread.current[:lux] = Struct.new(:uid, :request, :locale, :csrf).new('test123', request, 'en', 'test-csrf-token')
  end

  describe '#initialize' do
    it 'accepts string as action' do
      form = HtmlForm.new('/submit')
      _(form.opts[:action]).must_equal '/submit'
      _(form.object).must_be_nil
    end

    it 'defaults method to post' do
      form = HtmlForm.new
      _(form.opts[:method]).must_equal 'post'
    end

    it 'generates unique id' do
      form = HtmlForm.new
      _(form.opts[:id]).must_equal 'form-test123'
    end

    it 'accepts custom opts' do
      form = HtmlForm.new(action: '/foo', method: 'get')
      _(form.opts[:method]).must_equal 'get'
      _(form.opts[:action]).must_equal '/foo'
    end
  end

  describe '#render' do
    it 'renders form tag' do
      form = HtmlForm.new('/submit')
      html = form.render { |f| 'content' }

      assert_includes html, '<form'
      assert_includes html, '</form>'
      assert_includes html, 'content'
      assert_includes html, 'method="post"'
    end

    it 'renders an /api/ action as api-form with a default done' do
      html = HtmlForm.new('/api/foo/bar').render { |f| 'content' }

      assert_includes html, '<api-form'
      assert_includes html, '</api-form>'
      assert_includes html, 'done="refresh"'
      refute_includes html, 'lux-form'
    end

    it 'renders plain only when set' do
      refute_includes HtmlForm.new('/api/foo', plain: false).render { '' }, 'plain'
      assert_includes HtmlForm.new('/api/foo', plain: true).render { '' }, 'plain="true"'
    end

    it 'renders with pushed data' do
      form = HtmlForm.new('/submit')
      form.push '<input name="a">'
      form.push '<input name="b">'
      html = form.render

      assert_includes html, '<input name="a">'
      assert_includes html, '<input name="b">'
    end

    it 'wraps in disabled fieldset when disabled' do
      form = HtmlForm.new('/submit', disabled: true)
      html = form.render { 'content' }

      assert_includes html, '<fieldset'
      assert_includes html, 'disabled'
    end

    it 'adds enctype for file inputs' do
      form = HtmlForm.new('/upload')
      html = form.render { '<input type="file">' }

      assert_includes html, 'enctype="multipart/form-data"'
    end

    it 'skips enctype for get method' do
      form = HtmlForm.new('/search', method: 'get')
      html = form.render { '<input type="file">' }

      refute_includes html, 'enctype'
    end
  end

  describe '#input' do
    it 'renders input via HtmlInput' do
      form = HtmlForm.new
      html = form.input :email, as: :email

      assert_includes html, 'type="email"'
    end
  end

  describe '#row' do
    it 'renders labeled row with block' do
      form = HtmlForm.new
      html = form.row('Name') { '<input>' }

      assert_includes html, 'form-row'
      assert_includes html, 'Name'
      assert_includes html, '<input>'
    end

    it 'renders row with input' do
      form = HtmlForm.new
      html = form.row :name, as: :string, value: 'test'

      assert_includes html, 'form-row'
      assert_includes html, 'Name'
    end

    it 'renders hidden row directly' do
      form = HtmlForm.new
      html = form.row :token, as: :hidden, value: 'abc'

      assert_includes html, 'type="hidden"'
      refute_includes html, 'form-row'
    end

    it 'renders hint' do
      form = HtmlForm.new
      html = form.row :name, as: :string, hint: 'Enter your name'

      assert_includes html, 'Enter your name'
      assert_includes html, '<small'
    end

    it 'renders info' do
      form = HtmlForm.new
      html = form.row :name, as: :string, info: 'Required field'

      assert_includes html, 'Required field'
    end
  end

  describe '#submit' do
    it 'renders submit button' do
      form = HtmlForm.new
      html = form.submit 'Save'

      assert_includes html, 'type="submit"'
      assert_includes html, 'Save'
      assert_includes html, 'form-submit'
    end

    it 'defaults to create when no object' do
      form = HtmlForm.new
      html = form.submit

      assert_includes html, 'create'
      assert_includes html, 'ui-icon'
    end

    it 'renders cancel link' do
      form = HtmlForm.new
      html = form.submit 'Save', cancel: '/back'

      assert_includes html, 'href="/back"'
      assert_includes html, 'cancel'
    end

    it 'renders back link' do
      form = HtmlForm.new
      html = form.submit 'Save', back: '/list'

      assert_includes html, 'href="/list"'
      assert_includes html, 'go back'
    end

    it 'accepts hash as first argument' do
      form = HtmlForm.new
      html = form.submit class: 'btn-lg'

      assert_includes html, 'class="btn-lg"'
    end
  end

  describe '#fieldset' do
    it 'renders fieldset with title' do
      form = HtmlForm.new
      html = form.fieldset('Details') { 'content' }

      assert_includes html, '<fieldset>'
      assert_includes html, '<legend>Details</legend>'
      assert_includes html, 'content'
    end

    it 'renders fieldset with description' do
      form = HtmlForm.new
      html = form.fieldset('Details', 'Extra info') { 'content' }

      assert_includes html, 'Extra info'
    end

    it 'hides border when no title' do
      form = HtmlForm.new
      html = form.fieldset { 'content' }

      assert_includes html, 'border-top: none'
    end
  end
end
