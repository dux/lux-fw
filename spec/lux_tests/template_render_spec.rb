require 'test_helper'

describe 'Template Helper#render' do
  def views
    './spec/fixtures/views'
  end

  def with_error_log_buffer
    buf = StringIO.new
    logger = Logger.new(buf)
    logger.formatter = proc { |_, _, _, msg| "#{msg}\n" }

    prev = Lux.instance_variable_get(:@default_logger)
    Lux.instance_variable_set(:@default_logger, logger)
    yield buf
  ensure
    Lux.instance_variable_set(:@default_logger, prev)
  end

  # build a helper scope with the Helper module mixed in
  def build_helper(root_template_path = nil)
    scope = Object.new
    scope.extend Lux::Template::Helper
    Lux.current.var.views_root = views
    Lux.current.var.root_template_path = root_template_path
    scope
  end

  before do
    Lux::Current.new('http://test-render')
  end

  describe 'basic rendering' do
    it 'renders a template by absolute path' do
      helper = build_helper
      result = helper.render "#{views}/pages/index"
      _(result).must_include 'page:index'
    end

    it 'logs template exceptions before returning the inline fallback' do
      Dir.mkdir('./tmp') unless Dir.exist?('./tmp')
      File.write('./tmp/template_error_probe.haml', '= missing_method_for_log_probe')

      with_error_log_buffer do |buf|
        result = Lux::Template.render(Object.new, './tmp/template_error_probe')

        _(result).must_include 'lux-inline-error'
        _(buf.string).must_include '[NameError]'
        _(buf.string).must_include 'missing_method_for_log_probe'
      end
    end

    it 'renders a symbol as a relative path' do
      helper = build_helper("#{views}/pages")
      result = helper.render :_local
      _(result).must_include 'pages:local'
    end
  end

  describe 'relative path resolution' do
    it 'resolves partials relative to the calling template directory' do
      helper = build_helper("#{views}/pages")
      # _with_nested.haml calls render :_local, which should resolve
      # to pages/_local.haml (same directory)
      result = helper.render :_with_nested
      _(result).must_include 'pages:local'
    end

    it 'resolves cross-directory partials by path' do
      helper = build_helper("#{views}/pages")
      # _calls_shared.haml calls render 'shared/_widget'
      result = helper.render :_calls_shared
      _(result).must_include 'shared:widget'
    end

    it 'resolves nested cross-directory partials relative to their own directory' do
      helper = build_helper("#{views}/pages")
      # _calls_nested_shared.haml renders shared/_nested_widget
      # _nested_widget.haml renders :_widget (should resolve to shared/_widget, not pages/_widget)
      result = helper.render :_calls_nested_shared
      _(result).must_include 'shared:widget'
    end
  end

  describe 'root_template_path restoration' do
    it 'restores root_template_path after render so siblings resolve correctly' do
      helper = build_helper("#{views}/pages")
      # _sibling_test.haml renders shared/_widget then :_local
      # after the shared/ render, root should be restored to pages/
      # so :_local resolves to pages/_local
      result = helper.render :_sibling_test
      _(result).must_include 'shared:widget'
      _(result).must_include 'pages:local'
    end

    it 'restores root_template_path even if rendering raises' do
      helper = build_helper("#{views}/pages")
      original_root = Lux.current.var.root_template_path

      begin
        helper.render :_nonexistent
      rescue
      end

      _(Lux.current.var.root_template_path).must_equal original_root
    end
  end

  describe 'extension resolution' do
    it 'exposes every Tilt extension, including lazy engines like markdown' do
      exts = Lux::Template.tilt_extensions

      # md/markdown/mkd live in Tilt's lazy map - the resolver must see them
      # so .md views resolve natively, with the engine loaded on first render.
      _(exts).must_include 'md'
      _(exts).must_include 'markdown'
      _(exts).must_include 'haml'
    end
  end

  describe 'locals' do
    it 'passes locals to the rendered template' do
      helper = build_helper("#{views}/pages")
      result = helper.render :_show_local, item: 'world'
      _(result).must_include 'local:world'
    end

    it 'restores locals after render' do
      helper = build_helper("#{views}/pages")
      helper.instance_variable_set(:@_item, 'before')

      helper.render :_show_local, item: 'during'

      _(helper.instance_variable_get(:@_item)).must_equal 'before'
    end
  end
end

describe 'Template output escaping' do
  before do
    Lux::Current.new('http://test-escape')
    Lux.current.var.views_root = './spec/fixtures/views'
    Lux.current.var.root_template_path = nil
  end

  it 'escapes values, keeps markup, partials and helper blocks once' do
    scope = Object.new
    scope.extend Lux::Template::Helper
    scope.instance_variable_set :@name, '<x>'
    scope.instance_variable_set :@markup, '<u>m</u>'
    # a helper taking a template block: capture marks the block output as markup
    def scope.box(&block) = capture(&block).tag(:div, class: 'box')

    out = Lux::Template.render(scope, './spec/fixtures/views/escape/page')

    assert out.html_safe?
    _(out).must_include '<p>&lt;x&gt;</p>'
    _(out).must_include '<p><u>m</u></p>'
    _(out).must_include '<p><b>b</b></p>'
    _(out).must_include '<span>&lt;x&gt;</span>'
    _(out).must_include '<div class="box"><i>&lt;x&gt;</i>'
    refute_includes out, '&amp;'
  end
end

describe 'Template block called after its template line' do
  it 'returns markup from Haml lines and plain text from a bare expression' do
    Lux::Current.new('http://test-escape')
    blocks = []
    scope  = Object.new
    scope.define_singleton_method(:later) { |&block| blocks << block }

    Tilt.new('./spec/fixtures/views/escape/later.haml').render(scope)
    markup, text = blocks.map { _1.call('<x>') }

    assert markup.html_safe?
    _(markup).must_include '<b>&lt;x&gt;</b>'
    refute text.html_safe?
  end
end
