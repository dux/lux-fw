require 'spec_helper'
require_relative '../../plugins/auto_controller/auto_controller'

class AutoControllerTestController < Lux::Controller
  include Lux::AutoController

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

describe Lux::AutoController do
  def run_filter_for path
    Lux::Current.new("http://test/#{path}")
    ctrl = AutoControllerTestController.new
    ctrl.action(:run_filters) rescue nil
    ctrl.matched_filters
  end

  describe '#filter' do
    it 'matches single segment' do
      expect(run_filter_for('spaces')).to eq([:spaces])
    end

    it 'matches nested segments' do
      expect(run_filter_for('spaces/ref')).to eq([:spaces, :spaces_ref])
    end

    it 'matches deeply nested segments' do
      expect(run_filter_for('spaces/ref/admin')).to eq([:spaces, :spaces_ref, :spaces_ref_admin])
    end

    it 'matches second top-level filter when first does not match' do
      expect(run_filter_for('cash_book_entries')).to eq([:cash_book_entries])
    end

    it 'matches nested in second top-level filter' do
      expect(run_filter_for('cash_book_entries/ref')).to eq([:cash_book_entries, :cash_book_entries_ref])
    end

    it 'matches third top-level filter' do
      expect(run_filter_for('notes')).to eq([:notes])
    end

    it 'does not match unrelated path' do
      expect(run_filter_for('unknown')).to eq([])
    end
  end

  describe 'depth optimization' do
    it 'skips subsequent top-level filters after a match' do
      # /spaces matches :spaces, should NOT check :cash_book_entries or :notes
      result = run_filter_for('spaces')
      expect(result).to eq([:spaces])
      expect(result).not_to include(:cash_book_entries)
      expect(result).not_to include(:notes)
    end

    it 'skips subsequent top-level filters even when nested miss' do
      # /spaces matches at depth 0 but :ref misses at depth 1
      # :cash_book_entries at depth 0 should still be skipped
      result = run_filter_for('spaces')
      expect(result).to eq([:spaces])
    end

    it 'still checks siblings at same depth when prior sibling missed' do
      # /spaces/ref/settings - :ref matches, inside :ref block
      # :admin misses at depth 2, :settings should still be checked at depth 2
      result = run_filter_for('spaces/ref/settings')
      expect(result).to eq([:spaces, :spaces_ref, :spaces_ref_settings])
    end

    it 'skips sibling at same depth after a match' do
      # /spaces/ref/admin - :admin matches at depth 2
      # :settings at depth 2 should be skipped
      result = run_filter_for('spaces/ref/admin')
      expect(result).to include(:spaces_ref_admin)
      expect(result).not_to include(:spaces_ref_settings)
    end
  end

  describe 'hyphen normalization' do
    it 'matches hyphenated paths to underscored filter names' do
      expect(run_filter_for('cash-book-entries')).to eq([:cash_book_entries])
    end

    it 'matches nested hyphenated paths' do
      expect(run_filter_for('cash-book-entries/ref')).to eq([:cash_book_entries, :cash_book_entries_ref])
    end
  end
end
