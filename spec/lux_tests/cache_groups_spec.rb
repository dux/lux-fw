require 'test_helper'

# Standalone test DB + plugin load (mirrors db_plugin_spec bootstrap).
Object.send(:remove_const, :DB) if defined?(DB)
DB = Sequel.connect('postgres:///lux_fw_test')
DB.loggers.clear
Sequel::Model.plugin :dirty

require File.expand_path('../../plugins/db/loader.rb', __dir__)
Sequel::Model.plugin :ref_linker
Sequel::Model.plugin :lux_links
Sequel::Model.plugin :lux_hooks

DB.drop_table?(:cg_docs)
DB.drop_table?(:cg_spaces)

DB.create_table :cg_spaces do
  String :ref, primary_key: true
  String :name
  DateTime :created_at
  DateTime :updated_at
end

DB.create_table :cg_docs do
  String :ref, primary_key: true
  String :cg_space_ref
  DateTime :created_at
  DateTime :updated_at
end

class CgSpace < Sequel::Model(:cg_spaces)
  set_primary_key :ref
  unrestrict_primary_key

  named_caches :cg_docs, 'feed'   # :cg_docs symbol -> CgDoc must exist; 'feed' free-form
end

# no cache wiring here - CgSpace `named_caches :cg_docs` auto-binds this child
# via the cg_space_ref foreign key on first cache access.
class CgDoc < Sequel::Model(:cg_docs)
  set_primary_key :ref
  unrestrict_primary_key
end

# table reuse; declares a symbol group with no backing model + a free-form one
class CgBad < Sequel::Model(:cg_spaces)
  set_primary_key :ref
  unrestrict_primary_key

  named_caches :ghosts, 'tag'
end

describe 'named cache groups' do
  before do
    Lux.cache.clear
    DB[:cg_docs].delete
    DB[:cg_spaces].delete
    @space = CgSpace.create(ref: 's1', name: 'S')
  end

  describe '#cache_for' do
    it 'returns a stable, readable string key' do
      k = @space.cache_for(:cg_docs, :home)
      _(k).must_equal @space.cache_for(:cg_docs, :home)
      _(k).must_match %r{\ACgSpace/s1/cg_docs/[\d.]+/home\z}
    end

    it 'is decoupled from the master updated_at' do
      before = @space.cache_for(:cg_docs)
      @space.update(updated_at: Time.now + 60)
      _(@space.cache_for(:cg_docs)).must_equal before
    end

    it 'lets a string-declared group skip the model check' do
      _(@space.cache_for('feed', :x)).must_match %r{\ACgSpace/s1/feed/[\d.]+/x\z}
    end
  end

  describe '#cache_clear' do
    it 'bumps the version so the key changes' do
      before = @space.cache_for(:cg_docs)
      @space.cache_clear(:cg_docs)
      _(@space.cache_for(:cg_docs)).wont_equal before
    end

    it 'with no args bumps every declared group' do
      d = @space.cache_for(:cg_docs)
      f = @space.cache_for('feed')
      @space.cache_clear
      _(@space.cache_for(:cg_docs)).wont_equal d
      _(@space.cache_for('feed')).wont_equal f
    end
  end

  describe 'generated sugar' do
    it 'matches the generic form' do
      _(@space.cache_for_cg_docs(:x)).must_equal @space.cache_for(:cg_docs, :x)
    end
  end

  describe 'guards' do
    it 'raises on an undeclared group' do
      _ { @space.cache_for(:nope) }.must_raise ArgumentError
    end

    it 'raises when a symbol group has no backing model' do
      _ { CgBad.new(ref: 'b1').cache_for(:ghosts) }.must_raise ArgumentError
    end

    it 'allows a string group with no backing model' do
      _(CgBad.new(ref: 'b1').cache_for('tag')).must_match %r{\ACgBad/b1/tag/}
    end
  end

  describe 'auto-wired invalidation' do
    it 'bumps the parent group when a child is written (no declaration)' do
      before = @space.cache_for(:cg_docs)        # first access installs the hook
      CgDoc.create(ref: 'd1', cg_space_ref: 's1')
      _(@space.cache_for(:cg_docs)).wont_equal before
    end

    it 'only bumps the space named in the child foreign key' do
      other = CgSpace.create(ref: 's2', name: 'S2')
      @space.cache_for(:cg_docs)
      before_other = other.cache_for(:cg_docs)
      CgDoc.create(ref: 'd2', cg_space_ref: 's1')   # belongs to s1
      _(other.cache_for(:cg_docs)).must_equal before_other
    end
  end
end
