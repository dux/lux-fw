require 'test_helper'

class AutoControllerTestController < Lux::Controller
  include Lux::Controller::Auto

  attr_reader :matched_filters

  before do
    @matched_filters = []
  end

  def run_filters
    filter :spaces do
      @matched_filters << :spaces
      filter :ref do
        @matched_filters << :spaces_ref
        filter :admin do
          @matched_filters << :spaces_ref_admin
        end
        filter :settings do
          @matched_filters << :spaces_ref_settings
        end
      end
    end

    filter :cash_book_entries do
      @matched_filters << :cash_book_entries
      filter :ref do
        @matched_filters << :cash_book_entries_ref
      end
    end

    filter :notes do
      @matched_filters << :notes
    end
  end
end

###

describe Lux::Controller::Auto do
  def run_filter_for path
    Lux::Current.new("http://test/#{path}")
    ctrl = AutoControllerTestController.new
    ctrl.action(:run_filters) rescue nil
    ctrl.matched_filters
  end

  describe '#filter' do
    it 'matches single segment' do
      _(run_filter_for('spaces')).must_equal [:spaces]
    end

    it 'matches nested segments' do
      _(run_filter_for('spaces/ref')).must_equal [:spaces, :spaces_ref]
    end

    it 'matches deeply nested segments' do
      _(run_filter_for('spaces/ref/admin')).must_equal [:spaces, :spaces_ref, :spaces_ref_admin]
    end

    it 'matches second top-level filter when first does not match' do
      _(run_filter_for('cash_book_entries')).must_equal [:cash_book_entries]
    end

    it 'matches nested in second top-level filter' do
      _(run_filter_for('cash_book_entries/ref')).must_equal [:cash_book_entries, :cash_book_entries_ref]
    end

    it 'matches third top-level filter' do
      _(run_filter_for('notes')).must_equal [:notes]
    end

    it 'does not match unrelated path' do
      _(run_filter_for('unknown')).must_equal []
    end
  end

  describe 'sibling filters' do
    # Filters are not "skipped" after a match - every sibling at the same depth
    # is evaluated, they just do not match. The cursor is restored on block exit.
    it 'runs only the sibling whose segment matches' do
      result = run_filter_for('spaces')
      _(result).must_equal [:spaces]
      _(result).wont_include :cash_book_entries
      _(result).wont_include :notes
    end

    it 'leaves the cursor where it was when a nested filter misses' do
      # /spaces matches at depth 0 but :ref misses at depth 1, so the following
      # depth-0 siblings still compare against segment 0
      result = run_filter_for('spaces')
      _(result).must_equal [:spaces]
    end

    it 'checks a later sibling at the same depth when the prior one missed' do
      # /spaces/ref/settings - :ref matches, :admin misses at depth 2,
      # :settings is still evaluated at depth 2
      result = run_filter_for('spaces/ref/settings')
      _(result).must_equal [:spaces, :spaces_ref, :spaces_ref_settings]
    end

    it 'does not run a non-matching sibling after a match at the same depth' do
      result = run_filter_for('spaces/ref/admin')
      _(result).must_include :spaces_ref_admin
      _(result).wont_include :spaces_ref_settings
    end
  end

  describe 'hyphen normalization' do
    it 'matches hyphenated paths to underscored filter names' do
      _(run_filter_for('cash-book-entries')).must_equal [:cash_book_entries]
    end

    it 'matches nested hyphenated paths' do
      _(run_filter_for('cash-book-entries/ref')).must_equal [:cash_book_entries, :cash_book_entries_ref]
    end
  end

  describe 'route cursor composition' do
    # A controller mounted under a prefix (map 'x', 'x#auto') must not repeat
    # that prefix in its filters - filter reads lux.route, which the map scope
    # already advanced.
    it 'matches from the cursor, not from nav.path[0]' do
      Lux::Current.new('http://test/mounted/spaces')
      ctrl = AutoControllerTestController.new

      Lux.current.route.with_scope(1) do
        ctrl.action(:run_filters) rescue nil
      end

      _(ctrl.matched_filters).must_equal [:spaces]
    end

    it 'does not match the consumed mount segment' do
      Lux::Current.new('http://test/spaces/notes')
      ctrl = AutoControllerTestController.new

      Lux.current.route.with_scope(1) do
        ctrl.action(:run_filters) rescue nil
      end

      _(ctrl.matched_filters).must_equal [:notes]
    end

    it 'restores the cursor after a filter block' do
      Lux::Current.new('http://test/spaces/ref')
      ctrl = AutoControllerTestController.new
      ctrl.action(:run_filters) rescue nil

      _(Lux.current.route.path).must_equal %w[spaces ref]
    end
  end
end
