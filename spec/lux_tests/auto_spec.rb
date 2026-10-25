require 'test_helper'

%i(serve_static_files asset_root csrf).each do |k|
  Lux.config[k] = false unless Lux.config.key?(k)
end
Lux.config[:plugins] ||= []

# Nested `map` scopes inside a router route. Renders what matched and the
# cursor it is left with, so a missed scope must restore it.
class AutoSpecRouter < Lux::Router
  route do
    @matched = []

    map :spaces do
      @matched << :spaces
      map :ref do
        @matched << :spaces_ref
        map :admin do
          @matched << :spaces_ref_admin
        end
        map :settings do
          @matched << :spaces_ref_settings
        end
      end
    end

    map :cash_book_entries do
      @matched << :cash_book_entries
      map :ref do
        @matched << :cash_book_entries_ref
      end
    end

    map :notes do
      @matched << :notes
    end

    render text: "#{@matched.join(',')}|#{lux.route.path.join('/')}"
  end
end

# auto resolves a template from the route path. A classified id renders as its
# value, but the on-disk convention is a literal `ref` segment, so the resolver
# reads lux.route.normalized_path.
class RefTemplateRouter < Lux::Router
  template_root './spec/fixtures/views'
  views  'boards'
  layout false

  route { auto }
end

AUTO_SPEC_ROUTE ||= proc do
  nav.map_path

  map 'ref-tpl', RefTemplateRouter

  map 'mounted' do
    map 'spaces', AutoSpecRouter
    map AutoSpecRouter
  end

  map AutoSpecRouter
end

# `map :ref` matches classified id segments by type, so the classifier has to
# have run - a segment literally spelled "ref" is not one.
REF ||= 'a' * 16

describe 'Lux::Router route scopes and auto' do
  before { Lux.router.route(&AUTO_SPEC_ROUTE) }

  def matched_for path
    Lux.render.get("http://test/#{path}").body.split('|').first.to_s.split(',').map(&:to_sym)
  end

  describe 'map scopes' do
    it 'matches single segment' do
      _(matched_for('spaces')).must_equal [:spaces]
    end

    it 'matches nested segments' do
      _(matched_for("spaces/#{REF}")).must_equal [:spaces, :spaces_ref]
    end

    it 'matches deeply nested segments' do
      _(matched_for("spaces/#{REF}/admin")).must_equal [:spaces, :spaces_ref, :spaces_ref_admin]
    end

    it 'matches second top-level scope when first does not match' do
      _(matched_for('cash_book_entries')).must_equal [:cash_book_entries]
    end

    it 'matches nested in second top-level scope' do
      _(matched_for("cash_book_entries/#{REF}")).must_equal [:cash_book_entries, :cash_book_entries_ref]
    end

    it 'matches third top-level scope' do
      _(matched_for('notes')).must_equal [:notes]
    end

    it 'does not match unrelated path' do
      _(matched_for('unknown')).must_equal []
    end

    it 'does not match a literal ref segment' do
      _(matched_for('spaces/ref')).must_equal [:spaces]
    end
  end

  describe 'sibling scopes' do
    it 'runs only the sibling whose segment matches' do
      _(matched_for('spaces')).must_equal [:spaces]
    end

    it 'checks a later sibling at the same depth when the prior one missed' do
      _(matched_for("spaces/#{REF}/settings")).must_equal [:spaces, :spaces_ref, :spaces_ref_settings]
    end

    it 'does not run a non-matching sibling after a match at the same depth' do
      result = matched_for("spaces/#{REF}/admin")
      _(result).must_include :spaces_ref_admin
      _(result).wont_include :spaces_ref_settings
    end
  end

  describe 'hyphen normalization' do
    it 'matches hyphenated paths to underscored scope names' do
      _(matched_for('cash-book-entries')).must_equal [:cash_book_entries]
    end

    it 'matches nested hyphenated paths' do
      _(matched_for("cash-book-entries/#{REF}")).must_equal [:cash_book_entries, :cash_book_entries_ref]
    end
  end

  # regression: to_s on a classified id is its value, so building the template
  # path from lux.route.path looked for views/boards/<the-id>.haml
  describe 'auto template resolution' do
    def render_for path
      Lux.render.get("http://test/ref-tpl/#{path}".chomp('/')).body
    end

    it 'renders the collection template' do
      _(render_for('')).must_include 'boards:root'
    end

    it 'renders ref.haml for a classified id segment' do
      _(render_for(REF)).must_include 'boards:ref'
    end

    it 'passes the id through to the template' do
      _(render_for(REF)).must_include "ref=#{REF}"
    end

    it 'renders ref/edit.haml for a nested member action' do
      _(render_for("#{REF}/edit")).must_include 'boards:ref:edit'
    end

    # template lookup is by name, so a literal segment lands on the same file.
    # Only route matching (map :ref) tells the two apart, by type.
    it 'resolves a literal ref segment to the same template, with no id' do
      _(render_for('ref')).must_include 'boards:ref'
      _(render_for('ref')).must_include 'ref='
      _(Lux.current.nav.ref).must_be_nil
    end

    it 'answers 404 when no template matches' do
      _(Lux.render.get('http://test/ref-tpl/missing').status).must_equal 404
    end
  end

  describe 'route cursor composition' do
    # A router mounted under a prefix does not repeat that prefix in its
    # scopes - map reads lux.route, which the mount already advanced.
    it 'matches from the cursor, not from nav.path[0]' do
      _(matched_for('mounted/notes')).must_equal [:notes]
    end

    it 'does not match the consumed mount segment' do
      _(matched_for('mounted/spaces/notes')).must_equal [:notes]
    end

    it 'restores the cursor after the scopes ran' do
      _(Lux.render.get('http://test/spaces/ref').body.split('|').last).must_equal 'spaces/ref'
    end
  end
end
