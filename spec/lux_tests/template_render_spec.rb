require 'spec_helper'

describe 'Template Helper#render' do
  let(:views) { './spec/fixtures/views' }

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
      expect(result).to include('page:index')
    end

    it 'renders a symbol as a relative path' do
      helper = build_helper("#{views}/pages")
      result = helper.render :_local
      expect(result).to include('pages:local')
    end
  end

  describe 'relative path resolution' do
    it 'resolves partials relative to the calling template directory' do
      helper = build_helper("#{views}/pages")
      # _with_nested.haml calls render :_local, which should resolve
      # to pages/_local.haml (same directory)
      result = helper.render :_with_nested
      expect(result).to include('pages:local')
    end

    it 'resolves cross-directory partials by path' do
      helper = build_helper("#{views}/pages")
      # _calls_shared.haml calls render 'shared/_widget'
      result = helper.render :_calls_shared
      expect(result).to include('shared:widget')
    end

    it 'resolves nested cross-directory partials relative to their own directory' do
      helper = build_helper("#{views}/pages")
      # _calls_nested_shared.haml renders shared/_nested_widget
      # _nested_widget.haml renders :_widget (should resolve to shared/_widget, not pages/_widget)
      result = helper.render :_calls_nested_shared
      expect(result).to include('shared:widget')
    end
  end

  describe 'root_template_path restoration' do
    it 'restores root_template_path after render so siblings resolve correctly' do
      helper = build_helper("#{views}/pages")
      # _sibling_test.haml renders shared/_widget then :_local
      # after the shared/ render, root should be restored to pages/
      # so :_local resolves to pages/_local
      result = helper.render :_sibling_test
      expect(result).to include('shared:widget')
      expect(result).to include('pages:local')
    end

    it 'restores root_template_path even if rendering raises' do
      helper = build_helper("#{views}/pages")
      original_root = Lux.current.var.root_template_path

      begin
        helper.render :_nonexistent
      rescue
      end

      expect(Lux.current.var.root_template_path).to eq(original_root)
    end
  end

  describe 'locals' do
    it 'passes locals to the rendered template' do
      helper = build_helper("#{views}/pages")
      result = helper.render :_show_local, item: 'world'
      expect(result).to include('local:world')
    end

    it 'restores locals after render' do
      helper = build_helper("#{views}/pages")
      helper.instance_variable_set(:@_item, 'before')

      helper.render :_show_local, item: 'during'

      expect(helper.instance_variable_get(:@_item)).to eq('before')
    end
  end
end
