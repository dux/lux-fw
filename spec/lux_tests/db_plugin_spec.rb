require 'test_helper'

# ---------------------------------------------------------------------------
# Database bootstrap – standalone test DB so we never touch real data
# Connect directly via Sequel (not Lux::Db) since we manage our own test DB.
# ---------------------------------------------------------------------------

Object.send(:remove_const, :DB) if defined?(DB)
DB ||= Sequel.connect('postgres:///lux_fw_test')
DB.extension :pg_array
Sequel.extension :pg_array_ops

# Silence Sequel logger during tests
DB.loggers.clear

# Enable dirty tracking (needed for on_change)
Sequel::Model.plugin :dirty

# ---------------------------------------------------------------------------
# Load all DB plugins under test
# ---------------------------------------------------------------------------

# The plugin owns its own load order via loader.rb; just require it.
require File.expand_path('../../plugins/db/loader.rb', __dir__)

# Register Sequel plugins so models can use `plugin :name`.
# :lux_links and :parent_model are aliases of :ref_linker (kept for compat).
Sequel::Model.plugin :ref_linker
Sequel::Model.plugin :parent_model
Sequel::Model.plugin :lux_links
Sequel::Model.plugin :primary_keys
Sequel::Model.plugin :lux_hooks
Sequel::Model.plugin :lux_before_save
Sequel::Model.plugin :lux_create_limit

# ---------------------------------------------------------------------------
# Schema – create test tables fresh every run
# ---------------------------------------------------------------------------

DB.drop_table?(:enum_widgets)
DB.drop_table?(:bare_models)
DB.drop_table?(:both_polys)
DB.drop_table?(:memos)
DB.drop_table?(:notes)
DB.drop_table?(:projects)
DB.drop_table?(:tree_nodes)
DB.drop_table?(:org_users)
DB.drop_table?(:comments)
DB.drop_table?(:tasks)
DB.drop_table?(:users)

DB.create_table :users do
  String  :ref, primary_key: true
  String  :name
  String  :email
  Integer :age, default: 0
  column  :tags, 'text[]', default: Sequel.lit("'{}'")
  TrueClass :is_deleted, default: false
  TrueClass :is_active, default: true
  String  :step_sid, default: 'a'
  DateTime :created_at
  DateTime :updated_at
  String  :creator_ref
  String  :updater_ref
end

DB.create_table :tasks do
  String  :ref, primary_key: true
  String  :name
  String  :user_ref
  String  :parent_key
  String  :parent_type
  String  :parent_ref
  Integer :ord, default: 0
  column  :tags, 'text[]', default: Sequel.lit("'{}'")
  DateTime :created_at
  DateTime :updated_at
  String  :creator_ref
  String  :updater_ref
end

DB.create_table :comments do
  String  :ref, primary_key: true
  String  :body
  String  :task_ref
  String  :parent_key
  DateTime :created_at
  DateTime :updated_at
end

DB.create_table :org_users do
  String :ref, primary_key: true
  String :org_ref
  String :user_ref
  DateTime :created_at
  DateTime :updated_at
end

DB.create_table :tree_nodes do
  String  :ref, primary_key: true
  String  :name
  column  :parent_refs, 'text[]', default: Sequel.lit("ARRAY[]::text[]")
  DateTime :created_at
  DateTime :updated_at
end

DB.create_table :projects do
  String  :ref, primary_key: true
  String  :name
  column  :user_refs, 'text[]', default: Sequel.lit("'{}'")
  DateTime :created_at
  DateTime :updated_at
end

DB.create_table :notes do
  String  :ref, primary_key: true
  String  :body
  String  :parent_type
  String  :parent_ref
  String  :creator_ref
  DateTime :created_at
  DateTime :updated_at
end

# Polymorphic parent via `parent_model` (preferred name) instead of `parent_type`.
DB.create_table :memos do
  String  :ref, primary_key: true
  String  :body
  String  :parent_model
  String  :parent_ref
end

# Both poly-pair columns present: parent_model should win over parent_type.
DB.create_table :both_polys do
  String :ref, primary_key: true
  String :parent_model
  String :parent_type
  String :parent_ref
end

# No polymorphic columns at all: any parent write should `Lux.shell.die`.
DB.create_table :bare_models do
  String :ref, primary_key: true
  String :name
end

DB.create_table :enum_widgets do
  String   :ref, primary_key: true
  String   :status_sid, default: 'a'
  Integer  :level_id
  String   :mood_sid
  DateTime :created_at
  DateTime :updated_at
end

# ---------------------------------------------------------------------------
# Minimal User stub so before_save_filters (which guard on `defined?(User)`)
# and find_precache work.
# ---------------------------------------------------------------------------

class User < Sequel::Model
  set_primary_key :ref
  unrestrict_primary_key

  class << self
    attr_accessor :current
  end

  enum :step, values: { 'a' => 'Active', 'i' => 'Inactive', 'd' => 'Disabled' }
end

class Task < Sequel::Model
  set_primary_key :ref
  unrestrict_primary_key

  plugin :parent_model
  plugin :lux_links

  link :user
end

class Comment < Sequel::Model
  set_primary_key :ref
  unrestrict_primary_key
end

class OrgUser < Sequel::Model
  set_primary_key :ref
  unrestrict_primary_key

  plugin :primary_keys
  primary_keys :org_ref, :user_ref
end

class TreeNode < Sequel::Model
  set_primary_key :ref
  unrestrict_primary_key

  include ModelTree
end

class Project < Sequel::Model
  set_primary_key :ref
  unrestrict_primary_key

  plugin :lux_links
  link :users  # plural, array-based (user_refs text[])
end

class Note < Sequel::Model
  set_primary_key :ref
  unrestrict_primary_key

  plugin :parent_model
  plugin :lux_create_limit

  # .my scope required by create_limit (filters to current user's records)
  scope(:my) { |user = nil| where(creator_ref: (user || User.current).ref) }

  create_limit 3, 1.hour
end

class Memo < Sequel::Model
  set_primary_key :ref
  unrestrict_primary_key
  plugin :parent_model
end

class BothPoly < Sequel::Model(:both_polys)
  set_primary_key :ref
  unrestrict_primary_key
  plugin :parent_model
end

class BareModel < Sequel::Model(:bare_models)
  set_primary_key :ref
  unrestrict_primary_key
  plugin :parent_model
end

class EnumWidget < Sequel::Model(:enum_widgets)
  set_primary_key :ref
  unrestrict_primary_key

  plugin :lux_schema

  schema do
    enum :status, default: 'a' do |f|
      f[:a] = 'Active'
      f[:i] = 'Inactive'
      f[:d] = 'Disabled'
    end

    enum :level do |f|
      f[1] = 'Low'
      f[2] = 'Normal'
      f[3] = 'High'
    end

    enum :mood?, meta: { label: 'Mood' } do |f|
      f[:h] = 'Happy'
      f[:s] = 'Sad'
    end
  end
end

# Add plural reverse-lookup link after both classes exist
Comment.scope(:default) { self }
Task.plugin :lux_links
Task.class_eval { link :comments }

# Singular link setter was untested - Task already has `link :user`

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def new_ref
  Lux::Utils::Crypt.uid(12)
end

# Helper to create a record via model (with ref and timestamps handled)
def create_user(attrs = {})
  attrs[:ref] ||= new_ref
  User.create(attrs)
end

def create_task(attrs = {})
  attrs[:ref] ||= new_ref
  Task.create(attrs)
end

# Ensure a Lux::Current is always present (needed by find_precache & before_save).
# Each top-level describe in this file calls `db_plugin_setup` to install the
# per-test hook (replacement for the original RSpec :db_plugin metadata tag).
module DbPluginSetup
  def db_plugin_setup
    before do
      Lux::Current.new('http://test')
      User.current = nil
    end
  end
end
Minitest::Spec.extend(DbPluginSetup)

# =========================================================================
#  core.rb
# =========================================================================

describe 'plugins/db/core.rb' do
  db_plugin_setup
  before { DB[:users].delete }

  # -- ClassMethods --------------------------------------------------------

  describe 'Sequel::Model ClassMethods' do
    describe '.find_by' do
      it 'returns the first matching record' do
        ref = new_ref
        DB[:users].insert(ref: ref, name: 'Alice')
        user = User.find_by(name: 'Alice')
        _(user).must_be_kind_of User
        _(user.ref).must_equal ref
      end

      it 'returns nil when nothing matches' do
        _(User.find_by(name: 'Ghost')).must_be_nil
      end
    end

    describe '.scope' do
      before do
        User.scope(:named) { where(Sequel.lit("name is not null and name != ''")) }
      end

      it 'defines a dataset method usable as a chainable scope' do
        DB[:users].insert(ref: new_ref, name: 'Alice')
        DB[:users].insert(ref: new_ref, name: '')
        _(User.named.count).must_equal 1
      end
    end

    describe '.first_or_new' do
      it 'returns existing record if found' do
        ref = new_ref
        DB[:users].insert(ref: ref, name: 'Bob')
        user = User.first_or_new(ref: ref)
        _(user.name).must_equal 'Bob'
        _(user.new?).must_equal false
      end

      it 'returns a new unsaved record if not found' do
        user = User.first_or_new(name: 'Charlie')
        _(user.new?).must_equal true
        _(user.name).must_equal 'Charlie'
      end

      it 'yields block when object has no :id column value' do
        # Sequel#id returns @values[:id], which is nil for ref-based PKs,
        # so the block is yielded for both new and existing records.
        yielded = false
        User.first_or_new(name: 'Charlie') { |u| yielded = true }
        _(yielded).must_equal true
      end
    end

    describe '.first_or_create' do
      it 'creates a new record if not found' do
        user = User.first_or_create(name: 'Dave') { |u| u.ref ||= new_ref }
        _(user.new?).must_equal false
        _(User.where(name: 'Dave').count).must_equal 1
      end

      it 'returns existing record if found' do
        ref = new_ref
        DB[:users].insert(ref: ref, name: 'Eve')
        user = User.first_or_create(name: 'Eve')
        _(user.ref).must_equal ref
      end
    end
  end

  # -- InstanceMethods -----------------------------------------------------

  describe 'Sequel::Model InstanceMethods' do
    def ref
      @ref ||= new_ref
    end

    def user
      @user ||= begin
        DB[:users].insert(ref: ref, name: 'Alice', email: 'a@b.c', age: 30, updated_at: Time.now.utc)
        User[ref]
      end
    end

    before { user }  # eager (was let!)

    describe '#key' do
      it 'returns Class/ref format' do
        _(user.key).must_equal "User/#{ref}"
      end

      it 'appends namespace when given' do
        _(user.key(:notes)).must_equal "User/#{ref}/notes"
      end
    end

    describe '#cache_key' do
      it 'includes id and updated_at timestamp when available' do
        ck = user.cache_key
        _(ck).must_include 'User/'
        _(ck).must_include user.id.to_s
        _(ck).must_match(/-[\d.]+$/)
      end

      it 'appends namespace' do
        _(user.cache_key(:v2)).must_match(%r{/v2$})
      end

      it 'falls back to #key when no updated_at' do
        DB[:comments].insert(ref: 'c1', body: 'hi')
        comment = Comment['c1']
        _(comment.cache_key).must_equal comment.key
      end
    end

    describe '#attributes / #to_h' do
      it 'returns a hash of all column values as strings keys' do
        h = user.attributes
        _(h).must_be_kind_of Hash
        _(h['name']).must_equal 'Alice'
        _(h['ref']).must_equal ref
      end

      it 'is aliased as to_h' do
        _(user.to_h).must_equal user.attributes
      end
    end

    describe '#has?' do
      it 'returns true when field is present' do
        _(user.has?(:name)).must_equal true
      end

      it 'returns false when field is blank' do
        user[:name] = nil
        _(user.has?(:name)).must_equal false
      end

      it 'adds error and returns false with message string' do
        user[:email] = nil
        result = user.has?(:email, 'Email is required')
        _(result).must_equal false
        _(user.errors[:email]).must_include 'Email is required'
      end

      it 'returns true and adds no error when present with message' do
        result = user.has?(:name, 'Name required')
        _(result).must_equal true
        assert_empty user.errors
      end
    end

    describe '#unique?' do
      it 'returns true when no other record has same value' do
        _(user.unique?(:email)).must_equal true
      end

      it 'returns false when another record shares the value' do
        DB[:users].insert(ref: new_ref, name: 'Alice', email: 'a@b.c')
        _(user.unique?(:email)).must_equal false
      end
    end

    describe '#save!' do
      it 'saves without validation' do
        u = User.new
        u[:ref] = new_ref
        u[:name] = 'NoVal'
        u.save!
        _(User.where(name: 'NoVal').count).must_equal 1
      end
    end

    describe '#slice' do
      it 'returns a hash of requested fields' do
        h = user.slice(:name, :email)
        _(h).must_equal({ name: 'Alice', email: 'a@b.c' })
      end
    end

    describe '#merge' do
      it 'sets attributes from hash' do
        user.merge(name: 'Bob', email: 'b@c.d')
        _(user.name).must_equal 'Bob'
        _(user.email).must_equal 'b@c.d'
      end

      it 'ignores unknown keys' do
        user.merge(nonexistent_field: 'x')  # should not raise
      end
    end

    describe '#on_change' do
      # -- Primitives: replace, add, remove ---------------------------------

      it 'yields previous and new values when string replaced' do
        user.name = 'Zara'
        yielded = nil
        user.on_change(:name) { |prev, cur| yielded = [prev, cur] }
        _(yielded).must_equal ['Alice', 'Zara']
      end

      it 'yields when value added (nil -> value)' do
        # create user with nil email
        r = new_ref
        DB[:users].insert(ref: r, name: 'NoEmail', email: nil)
        u = User[r]

        u.email = 'new@test.com'
        yielded = nil
        u.on_change(:email) { |prev, cur| yielded = [prev, cur] }
        _(yielded).must_equal [nil, 'new@test.com']
      end

      it 'yields when value removed (value -> nil)' do
        user.name = nil
        yielded = nil
        user.on_change(:name) { |prev, cur| yielded = [prev, cur] }
        _(yielded).must_equal ['Alice', nil]
      end

      it 'yields when integer replaced' do
        user.age = 40
        yielded = nil
        user.on_change(:age) { |prev, cur| yielded = [prev, cur] }
        _(yielded).must_equal [30, 40]
      end

      it 'yields when boolean replaced' do
        user.is_active = false
        yielded = nil
        user.on_change(:is_active) { |prev, cur| yielded = [prev, cur] }
        _(yielded).must_equal [true, false]
      end

      it 'does not yield when column unchanged' do
        yielded = false
        user.on_change(:name) { yielded = true }
        _(yielded).must_equal false
      end

      # -- Arrays: add, remove, replace, set, clear --------------------------

      it 'yields when array element added' do
        r = new_ref
        DB[:users].insert(ref: r, name: 'Tagged', tags: Sequel.pg_array(['ruby']))
        u = User[r]

        u.tags = Sequel.pg_array(['ruby', 'js'])
        yielded = nil
        u.on_change(:tags) { |prev, cur| yielded = [prev, cur] }
        _(yielded[0]).must_equal ['ruby']
        _(yielded[1]).must_equal ['ruby', 'js']
      end

      it 'yields when array element removed' do
        r = new_ref
        DB[:users].insert(ref: r, name: 'Tagged', tags: Sequel.pg_array(['ruby', 'js']))
        u = User[r]

        u.tags = Sequel.pg_array(['ruby'])
        yielded = nil
        u.on_change(:tags) { |prev, cur| yielded = [prev, cur] }
        _(yielded[0]).must_equal ['ruby', 'js']
        _(yielded[1]).must_equal ['ruby']
      end

      it 'yields when array element replaced' do
        r = new_ref
        DB[:users].insert(ref: r, name: 'Tagged', tags: Sequel.pg_array(['ruby']))
        u = User[r]

        u.tags = Sequel.pg_array(['go'])
        yielded = nil
        u.on_change(:tags) { |prev, cur| yielded = [prev, cur] }
        _(yielded[0]).must_equal ['ruby']
        _(yielded[1]).must_equal ['go']
      end

      it 'yields when array set from empty' do
        r = new_ref
        DB[:users].insert(ref: r, name: 'Empty', tags: Sequel.pg_array([], :text))
        u = User[r]

        u.tags = Sequel.pg_array(['ruby'])
        yielded = nil
        u.on_change(:tags) { |prev, cur| yielded = [prev, cur] }
        _(yielded[0]).must_equal []
        _(yielded[1]).must_equal ['ruby']
      end

      it 'yields when array cleared' do
        r = new_ref
        DB[:users].insert(ref: r, name: 'Tagged', tags: Sequel.pg_array(['ruby']))
        u = User[r]

        u.tags = Sequel.pg_array([], :text)
        yielded = nil
        u.on_change(:tags) { |prev, cur| yielded = [prev, cur] }
        _(yielded[0]).must_equal ['ruby']
        _(yielded[1]).must_equal []
      end

      it 'does not yield when array unchanged' do
        r = new_ref
        DB[:users].insert(ref: r, name: 'Tagged', tags: Sequel.pg_array(['ruby']))
        u = User[r]

        yielded = false
        u.on_change(:tags) { yielded = true }
        _(yielded).must_equal false
      end

      # -- Multiple fields ---------------------------------------------------

      it 'yields independently for each changed field' do
        user.name = 'Bob'
        user.age = 99

        name_change = nil
        age_change = nil
        user.on_change(:name) { |prev, cur| name_change = [prev, cur] }
        user.on_change(:age) { |prev, cur| age_change = [prev, cur] }

        _(name_change).must_equal ['Alice', 'Bob']
        _(age_change).must_equal [30, 99]
      end

      it 'does not yield for unchanged field when other fields changed' do
        user.name = 'Bob'

        yielded = false
        user.on_change(:age) { yielded = true }
        _(yielded).must_equal false
      end
    end
  end

  # -- DatasetMethods (in core.rb) -----------------------------------------

  describe 'Sequel::Model DatasetMethods (core)' do
    before do
      DB[:users].delete
      3.times { |i| DB[:users].insert(ref: new_ref, name: "U#{i}", updated_at: Time.now.utc - (i * 60)) }
    end

    describe '.refs' do
      it 'returns array of ref strings' do
        result = User.dataset.refs
        _(result).must_be_kind_of Array
        _(result.length).must_equal 3
        result.each { |r| _(r).must_be_kind_of String }
      end

      it 'respects limit' do
        _(User.dataset.refs(2).length).must_equal 2
      end
    end

    describe '.latest' do
      it 'orders by updated_at descending' do
        times = User.dataset.latest.select_map(:updated_at)
        times.each_cons(2) { |a, b| assert a >= b }
      end
    end
  end
end

# =========================================================================
#  dataset_methods.rb
# =========================================================================

describe 'plugins/db/dataset_methods.rb' do
  db_plugin_setup
  before do
    DB[:users].delete
    DB[:tasks].delete
  end

  describe '.random' do
    it 'returns records in non-deterministic order without error' do
      3.times { |i| DB[:users].insert(ref: new_ref, name: "R#{i}") }
      _(User.dataset.random.all.length).must_equal 3
    end
  end

  describe '.xwhere' do
    before do
      DB[:users].insert(ref: new_ref, name: 'Alice', age: 25)
      DB[:users].insert(ref: new_ref, name: 'Bob', age: 30)
      DB[:users].insert(ref: new_ref, name: '', age: 0)
    end

    it 'returns self when given nil' do
      _(User.dataset.xwhere(nil).count).must_equal 3
    end

    it 'handles symbol to check non-blank' do
      # coalesce(name,'')!=''
      _(User.dataset.xwhere(:name).count).must_equal 2
    end

    it 'handles raw SQL string' do
      _(User.dataset.xwhere('age > ?', 26).count).must_equal 1
    end

    it 'handles hash conditions with present values' do
      _(User.dataset.xwhere(name: 'Alice').count).must_equal 1
    end

    it 'filters out blank hash values' do
      # blank values are removed from hash conditions
      _(User.dataset.xwhere(name: '').count).must_equal 3
    end

    describe 'with postgres arrays' do
      before do
        DB[:users].delete
        DB[:users].insert(ref: new_ref, name: 'Tagged', tags: Sequel.pg_array(['ruby', 'js']))
      end

      it 'searches for single element in array column' do
        _(User.dataset.xwhere(tags: 'ruby').count).must_equal 1
      end

      it 'searches for multiple elements with join type' do
        _(User.dataset.xwhere({ tags: ['ruby', 'js'] }, 'and').count).must_equal 1
        _(User.dataset.xwhere({ tags: ['ruby', 'python'] }, 'or').count).must_equal 1
      end
    end
  end

  describe '.xlike' do
    before do
      DB[:users].insert(ref: new_ref, name: 'Alice Smith')
      DB[:users].insert(ref: new_ref, name: 'Bob Jones')
    end

    it 'performs case-insensitive search' do
      _(User.dataset.xlike('alice', :name).count).must_equal 1
    end

    it 'searches across multiple fields' do
      DB[:users].insert(ref: new_ref, name: 'Charlie', email: 'charlie@test.com')
      _(User.dataset.xlike('charlie', :name, :email).count).must_equal 1
    end

    it 'handles multi-word search (AND logic between words)' do
      _(User.dataset.xlike('alice smith', :name).count).must_equal 1
      _(User.dataset.xlike('alice jones', :name).count).must_equal 0
    end

    it 'returns self for blank search' do
      _(User.dataset.xlike('', :name).count).must_equal 2
      _(User.dataset.xlike(nil, :name).count).must_equal 2
    end

    it 'raises for unknown fields' do
      err = _ { User.dataset.xlike('x', :nonexistent_column).all }.must_raise ArgumentError
      _(err.message).must_match(/not found/)
    end
  end

  describe '.last_updated' do
    it 'returns the most recently updated record' do
      old_ref = new_ref
      new_r = new_ref
      DB[:users].insert(ref: old_ref, name: 'Old', updated_at: Time.now.utc - 3600)
      DB[:users].insert(ref: new_r, name: 'New', updated_at: Time.now.utc)
      _(User.dataset.last_updated.ref).must_equal new_r
    end

    it 'applies optional filter' do
      DB[:users].insert(ref: new_ref, name: 'A', age: 1, updated_at: Time.now.utc)
      DB[:users].insert(ref: new_ref, name: 'B', age: 2, updated_at: Time.now.utc - 100)
      _(User.dataset.last_updated(age: 2).name).must_equal 'B'
    end
  end

  describe '.for' do
    it 'scopes by foreign ref field' do
      u_ref = new_ref
      DB[:users].insert(ref: u_ref, name: 'Alice')
      DB[:tasks].insert(ref: new_ref, name: 'T1', user_ref: u_ref)
      DB[:tasks].insert(ref: new_ref, name: 'T2', user_ref: 'other')

      user = User[u_ref]
      _(Task.dataset.for(user).count).must_equal 1
      _(Task.dataset.for(user).first.name).must_equal 'T1'
    end
  end

  describe '.desc / .asc' do
    before do
      DB[:users].insert(ref: new_ref, name: 'A', created_at: Time.now.utc - 200)
      DB[:users].insert(ref: new_ref, name: 'B', created_at: Time.now.utc - 100)
      DB[:users].insert(ref: new_ref, name: 'C', created_at: Time.now.utc)
    end

    it '.desc orders newest first by default' do
      _(User.dataset.desc.first.name).must_equal 'C'
    end

    it '.desc accepts custom field' do
      _(User.dataset.desc(:name).first.name).must_equal 'C'
    end

    it '.asc orders oldest first' do
      _(User.dataset.asc.first.name).must_equal 'A'
    end
  end

  describe '.pluck' do
    it 'returns array of single field values' do
      DB[:users].insert(ref: new_ref, name: 'X')
      DB[:users].insert(ref: new_ref, name: 'Y')
      names = User.dataset.pluck(:name)
      _(names.sort).must_equal ['X', 'Y']
    end
  end

  describe '.last' do
    before do
      DB[:users].insert(ref: new_ref, name: 'A', created_at: Time.now.utc - 200)
      DB[:users].insert(ref: new_ref, name: 'B', created_at: Time.now.utc - 100)
      DB[:users].insert(ref: new_ref, name: 'C', created_at: Time.now.utc)
    end

    it 'returns single most recent record without argument' do
      _(User.dataset.last.name).must_equal 'C'
    end

    it 'returns array of N records with argument' do
      result = User.dataset.last(2)
      _(result.length).must_equal 2
      _(result.first.name).must_equal 'C'
    end
  end
end

# =========================================================================
#  find_precache.rb
# =========================================================================

describe 'plugins/db/find_precache.rb' do
  db_plugin_setup
  before { DB[:users].delete }

  def ref
    @ref ||= new_ref
  end

  before do
    DB[:users].insert(ref: ref, name: 'Cached')
  end

  describe '.find' do
    it 'returns the record by ref' do
      user = User.find(ref)
      _(user).must_be_kind_of User
      _(user.name).must_equal 'Cached'
    end

    it 'raises when not found' do
      err = _ { User.find('nonexistent') }.must_raise Sequel::Error
      _(err.message).must_match(/not found/)
    end

    it 'returns nil for blank id' do
      _(User.find(nil)).must_be_nil
      _(User.find('')).must_be_nil
    end

    it 'caches within the same request scope' do
      user1 = User.find(ref)
      user2 = User.find(ref)
      _(user1.object_id).must_equal user2.object_id
    end
  end

  describe '.take' do
    it 'returns the record when found' do
      _(User.take(ref).name).must_equal 'Cached'
    end

    it 'returns nil instead of raising when not found' do
      _(User.take('nonexistent')).must_be_nil
    end
  end
end

# =========================================================================
#  before_save_filters.rb
# =========================================================================

describe 'plugins/db/before_save_filters.rb' do
  db_plugin_setup
  before do
    DB[:users].delete
    User.current = nil
  end

  describe 'timestamp handling' do
    it 'sets created_at on new records' do
      u = create_user(name: 'New')
      refute_nil u.created_at
      assert_in_delta Time.now.utc, u.created_at, 2
    end

    it 'sets updated_at on every save' do
      u = create_user(name: 'Up')
      original_updated = u.updated_at
      sleep 0.01
      u.update(name: 'Updated')
      assert u.updated_at > original_updated
    end
  end

  describe 'audit columns' do
    def current_user
      @current_user ||= begin
        ref = new_ref
        DB[:users].insert(ref: ref, name: 'Admin')
        User[ref]
      end
    end

    it 'sets creator_ref on create when user is logged in' do
      User.current = current_user
      u = create_user(name: 'Created')
      _(u.creator_ref).must_equal current_user.ref
    end

    it 'sets updater_ref on save when user is logged in' do
      User.current = current_user
      u = create_user(name: 'A')
      _(u.updater_ref).must_equal current_user.ref
    end

    it 'leaves audit columns nil when no current user' do
      User.current = nil
      u = create_user(name: 'NoAudit')
      _(u.creator_ref).must_be_nil
    end
  end

  describe 'soft delete' do
    it 'sets is_deleted instead of destroying when is_deleted column exists' do
      u = create_user(name: 'SoftDel')
      u.destroy
      row = DB[:users].where(ref: u.ref).first
      refute_nil row
      _(row[:is_deleted]).must_equal true
    end
  end

  describe 'dataset scopes' do
    before do
      DB[:users].insert(ref: new_ref, name: 'Active', is_deleted: false, is_active: true)
      DB[:users].insert(ref: new_ref, name: 'Deleted', is_deleted: true, is_active: true)
      DB[:users].insert(ref: new_ref, name: 'Inactive', is_deleted: false, is_active: false)
    end

    it '.not_deleted excludes soft-deleted records' do
      names = User.dataset.not_deleted.select_map(:name)
      _(names).must_include 'Active'
      _(names).must_include 'Inactive'
      _(names).wont_include 'Deleted'
    end

    it '.deleted returns only soft-deleted records' do
      names = User.dataset.deleted.select_map(:name)
      _(names).must_equal ['Deleted']
    end

    it '.activated returns only active records' do
      names = User.dataset.activated.select_map(:name)
      _(names).must_include 'Active'
      _(names).wont_include 'Inactive'
    end

    it '.deactivated returns only inactive records' do
      names = User.dataset.deactivated.select_map(:name)
      _(names).must_equal ['Inactive']
    end
  end
end

# =========================================================================
#  enums_plugin.rb
# =========================================================================

describe 'plugins/db/enums_plugin.rb' do
  db_plugin_setup
  before { DB[:users].delete }

  # User already has: enum :step, values: { 'a'=>'Active', 'i'=>'Inactive', 'd'=>'Disabled' }

  describe '.enum class method' do
    it 'defines a class method returning all values' do
      _(User.steps).must_equal({ 'a' => 'Active', 'i' => 'Inactive', 'd' => 'Disabled' }.to_lux_hash)
    end

    it 'returns single value when called with id' do
      _(User.steps('a')).must_equal 'Active'
      _(User.steps('d')).must_equal 'Disabled'
    end
  end

  describe 'instance enum methods' do
    def user
      @user ||= begin
        DB[:users].insert(ref: new_ref, name: 'EnumUser', step_sid: 'i')
        User.where(name: 'EnumUser').first
      end
    end

    it '#step_sid returns the stored value or default' do
      _(user.step_sid).must_equal 'i'
    end

    it '#step returns the human name' do
      _(user.step).must_equal 'Inactive'
    end

    it 'returns default when field is blank' do
      DB[:users].insert(ref: new_ref, name: 'Default', step_sid: nil)
      u = User.where(name: 'Default').first
      _(u.step_sid).must_equal 'a' # default
      _(u.step).must_equal 'Active'
    end
  end

  describe 'array-based enums' do
    before do
      User.enum :priority, ['low', 'medium', 'high']
    end

    it 'creates the class method with all keys' do
      vals = User.priorities
      _(vals.keys.sort).must_equal ['high', 'low', 'medium']
    end

    it 'returns nil values (array enums store key only)' do
      # array-based enums produce { 'low' => nil, 'medium' => nil, 'high' => nil }
      # because Array elements destructure as (key, nil) pairs
      _(User.priorities['low']).must_be_nil
    end

    it 'has no field (field: false for array-based)' do
      # no field defined, so only the class-level lookup is created
      assert_respond_to User.priorities, :keys
    end
  end
end

# =========================================================================
#  hooks.rb
# =========================================================================

describe 'plugins/db/hooks.rb' do
  db_plugin_setup
  before do
    DB[:tasks].delete
    # Hooks registered via Task.before(:c) {...} accumulate on the Task
    # class in HOOK_METHODS. Without this reset, a hook from one test
    # (e.g. validation that adds errors) blows up every subsequent test.
    Sequel::Plugins::LuxHooks::HOOK_METHODS.delete(Task)
  end

  describe 'before/after hooks' do
    it 'fires before(:c) on create' do
      fired = []
      Task.before(:c) { fired << :before_create }
      create_task(name: 'Hook')
      _(fired).must_include :before_create
    end

    it 'fires after(:c) on create' do
      fired = []
      Task.after(:c) { fired << :after_create }
      create_task(name: 'Hook')
      _(fired).must_include :after_create
    end

    it 'fires before(:u) on update' do
      fired = []
      Task.before(:u) { fired << :before_update }
      t = create_task(name: 'Hook')
      t.update(name: 'Updated')
      _(fired).must_include :before_update
    end

    it 'fires after(:u) on update' do
      fired = []
      Task.after(:u) { fired << :after_update }
      t = create_task(name: 'Hook')
      t.update(name: 'Updated')
      _(fired).must_include :after_update
    end

    it 'fires before(:d) on destroy' do
      fired = []
      Task.before(:d) { fired << :before_destroy }
      t = create_task(name: 'Hook')
      t.destroy
      _(fired).must_include :before_destroy
    end

    it 'fires after(:d) on destroy' do
      fired = []
      Task.after(:d) { fired << :after_destroy }
      t = create_task(name: 'Hook')
      t.destroy
      _(fired).must_include :after_destroy
    end

    it 'supports combined hooks like before(:cu)' do
      fired = []
      Task.before(:cu) { fired << :before_cu }
      create_task(name: 'A')
      _(fired.count(:before_cu)).must_equal 1 # create

      t = create_task(name: 'B')
      fired.clear
      t.update(name: 'C')
      _(fired.count(:before_cu)).must_equal 1 # update
    end

    it 'fires before(:v) before validation' do
      fired = []
      Task.before(:v) { fired << :before_validate }
      create_task(name: 'Hook')
      _(fired).must_include :before_validate
    end

    it 'fires before(:v) before before(:c)' do
      order = []
      Task.before(:v) { order << :validate }
      Task.before(:c) { order << :create }
      create_task(name: 'Order')
      _(order).must_equal [:validate, :create]
    end

    it 'fires before(:v) on update too' do
      fired = []
      Task.before(:v) { fired << :before_validate }
      t = create_task(name: 'Hook')
      fired.clear
      t.update(name: 'Updated')
      _(fired).must_include :before_validate
    end

    it 'supports before(:vc) combined hook' do
      fired = []
      Task.before(:vc) { fired << :before_vc }
      create_task(name: 'Combined')
      _(fired).must_include :before_vc
    end
  end

  describe 'before hooks with errors prevent save' do
    before do
      Sequel::Plugins::LuxHooks::HOOK_METHODS.delete(Task)
    end

    it 'before(:c) errors prevent record creation' do
      Task.before(:c) { errors.add(:name, 'is invalid') }
      err = _ { create_task(name: 'Blocked') }.must_raise Sequel::ValidationFailed
      _(err.message).must_match(/is invalid/)
      _(DB[:tasks].count).must_equal 0
    end

    it 'before(:u) errors prevent record update' do
      t = create_task(name: 'Original')
      Task.before(:u) { errors.add(:name, 'cannot change') }
      err = _ { t.update(name: 'Changed') }.must_raise Sequel::ValidationFailed
      _(err.message).must_match(/cannot change/)
      _(t.reload.name).must_equal 'Original'
    end

    it 'before(:d) errors prevent record destruction' do
      t = create_task(name: 'Keep')
      Task.before(:d) { errors.add(:base, 'cannot delete') }
      err = _ { t.destroy }.must_raise Sequel::ValidationFailed
      _(err.message).must_match(/cannot delete/)
      _(DB[:tasks].count).must_equal 1
    end

    it 'before(:v) errors prevent save via standard validation' do
      Task.before(:v) { errors.add(:name, 'bad name') }
      err = _ { create_task(name: 'Blocked') }.must_raise Sequel::ValidationFailed
      _(err.message).must_match(/bad name/)
      _(DB[:tasks].count).must_equal 0
    end

    it 'error messages are preserved in the exception' do
      Task.before(:c) { errors.add(:name, 'too short'); errors.add(:name, 'is blank') }
      begin
        create_task(name: 'Fail')
      rescue Sequel::ValidationFailed => e
        _(e.errors[:name]).must_include 'too short'
        _(e.errors[:name]).must_include 'is blank'
      end
    end

    it 'after hooks do not trigger validation check' do
      Task.after(:c) { errors.add(:name, 'should not matter') }
      create_task(name: 'OK')  # should not raise
      _(DB[:tasks].count).must_equal 1
    end
  end
end

# =========================================================================
#  _parent_model.rb
# =========================================================================

describe 'plugins/db/_parent_model.rb' do
  db_plugin_setup
  before do
    DB[:users].delete
    DB[:tasks].delete
  end

  def user_ref
    @user_ref ||= new_ref
  end

  def user
    @user ||= begin
      DB[:users].insert(ref: user_ref, name: 'Parent')
      User[user_ref]
    end
  end

  before { user }  # eager (was let!)

  describe '#parent= and #parent (parent_key style)' do
    it 'sets parent via parent_key' do
      t = Task.new
      t[:ref] = new_ref
      t[:name] = 'T'
      t.parent = user
      _(t[:parent_key]).must_equal "User/#{user_ref}"
    end

    it 'retrieves parent from parent_key' do
      t_ref = new_ref
      DB[:tasks].insert(ref: t_ref, name: 'T', parent_key: "User/#{user_ref}")
      t = Task[t_ref]
      _(t.parent).must_be_kind_of User
      _(t.parent.ref).must_equal user_ref
    end

    it 'accepts a string key in Class/ref format' do
      t = Task.new
      t[:ref] = new_ref
      t.parent = "User/#{user_ref}"
      _(t[:parent_key]).must_equal "User/#{user_ref}"
    end
  end

  describe '#parent?' do
    it 'returns truthy when parent columns exist' do
      t = Task.new
      assert t.parent?
    end
  end

  describe '.where_ref (parent_key fallback)' do
    # Comment has parent_key but no user_ref, so where_ref falls through
    # the scalar/array shapes and lands on parent_key.
    it 'scopes records to given parent via parent_key' do
      DB[:comments].delete
      DB[:comments].insert(ref: new_ref, body: 'C1', parent_key: "User/#{user_ref}")
      DB[:comments].insert(ref: new_ref, body: 'C2', parent_key: 'User/other')

      comments = Comment.where_ref(user)
      _(comments.count).must_equal 1
      _(comments.first.body).must_equal 'C1'
    end
  end

  describe 'DatasetMethods#for (parent_key fallback)' do
    it 'filters dataset by parent_key' do
      DB[:comments].delete
      DB[:comments].insert(ref: new_ref, body: 'C1', parent_key: "User/#{user_ref}")
      DB[:comments].insert(ref: new_ref, body: 'C2', parent_key: 'User/other')

      _(Comment.dataset.for(user).count).must_equal 1
    end
  end
end

# =========================================================================
#  link_objects.rb
# =========================================================================

describe 'plugins/db/link_objects.rb' do
  db_plugin_setup
  before do
    DB[:users].delete
    DB[:tasks].delete
  end

  def user_ref
    @user_ref ||= new_ref
  end

  def user
    @user ||= begin
      DB[:users].insert(ref: user_ref, name: 'Owner')
      User[user_ref]
    end
  end

  before { user }  # eager-create owner (was let!)

  describe 'DatasetMethods#where_ref' do
    it 'scopes by foreign ref column' do
      DB[:tasks].insert(ref: new_ref, name: 'T1', user_ref: user_ref)
      DB[:tasks].insert(ref: new_ref, name: 'T2', user_ref: 'other')

      _(Task.dataset.where_ref(user).count).must_equal 1
    end

    it 'returns self when object is nil' do
      DB[:tasks].insert(ref: new_ref, name: 'T1')
      _(Task.dataset.where_ref(nil).count).must_equal 1
    end
  end

  describe 'ClassMethods.where_ref' do
    it 'delegates to dataset' do
      DB[:tasks].insert(ref: new_ref, name: 'T1', user_ref: user_ref)
      _(Task.where_ref(user).count).must_equal 1
    end
  end

  describe 'ref singular (belongs_to)' do
    it 'defines getter that returns associated model' do
      t_ref = new_ref
      DB[:tasks].insert(ref: t_ref, name: 'T', user_ref: user_ref)
      task = Task[t_ref]
      _(task.user).must_be_kind_of User
      _(task.user.ref).must_equal user_ref
    end

    it 'returns nil when ref is blank' do
      t_ref = new_ref
      DB[:tasks].insert(ref: t_ref, name: 'T', user_ref: nil)
      task = Task[t_ref]
      _(task.user).must_be_nil
    end
  end
end

# =========================================================================
#  composite_primary_keys.rb
# =========================================================================

describe 'plugins/db/composite_primary_keys.rb' do
  db_plugin_setup
  before { DB[:org_users].delete }

  describe '.primary_keys' do
    it 'returns defined composite keys' do
      _(OrgUser.primary_keys).must_equal [:org_ref, :user_ref]
    end
  end

  describe 'uniqueness enforcement on save' do
    it 'allows first record with given key combination' do
      OrgUser.create(ref: new_ref, org_ref: 'org1', user_ref: 'u1')  # should not raise
    end

    it 'raises when duplicate composite key is inserted' do
      OrgUser.create(ref: new_ref, org_ref: 'org1', user_ref: 'u1')
      err = _ { OrgUser.create(ref: new_ref, org_ref: 'org1', user_ref: 'u1') }.must_raise StandardError
      _(err.message).must_match(/already exists/)
    end

    it 'allows same org_ref with different user_ref' do
      OrgUser.create(ref: new_ref, org_ref: 'org1', user_ref: 'u1')
      OrgUser.create(ref: new_ref, org_ref: 'org1', user_ref: 'u2')  # should not raise
    end
  end
end

# =========================================================================
#  array_search.rb
# =========================================================================

describe 'plugins/db/array_search.rb' do
  db_plugin_setup
  before { DB[:users].delete }

  describe '.all_tags' do
    before do
      DB[:users].insert(ref: new_ref, name: 'A', tags: Sequel.pg_array(['ruby', 'js']))
      DB[:users].insert(ref: new_ref, name: 'B', tags: Sequel.pg_array(['ruby', 'python']))
      DB[:users].insert(ref: new_ref, name: 'C', tags: Sequel.pg_array(['go']))
    end

    it 'returns tag names with counts' do
      result = User.dataset.all_tags
      _(result).must_be_kind_of Array
      names = result.map { |r| r[:name] || r['name'] }
      _(names).must_include 'ruby'
    end

    it 'respects limit' do
      result = User.dataset.all_tags(limit: 2)
      assert result.length <= 2
    end

    it 'works with custom field name' do
      result = User.dataset.all_tags(tags: :tags, limit: 10)
      _(result).must_be_kind_of Array
    end
  end

  describe '.where_any' do
    before do
      DB[:users].insert(ref: new_ref, name: 'A', tags: Sequel.pg_array(['ruby', 'js']))
      DB[:users].insert(ref: new_ref, name: 'B', tags: Sequel.pg_array(['python']))
      DB[:users].insert(ref: new_ref, name: 'C', tags: Sequel.pg_array(['ruby', 'go']))
    end

    it 'finds records with any matching tag' do
      _(User.dataset.where_any('ruby', :tags).count).must_equal 2
    end

    it 'accepts array of values' do
      _(User.dataset.where_any(['ruby', 'python'], :tags).count).must_equal 3
    end

    it 'returns self when data is blank' do
      _(User.dataset.where_any(nil, :tags).count).must_equal 3
      _(User.dataset.where_any('', :tags).count).must_equal 3
    end
  end

  describe '.where_all' do
    before do
      DB[:users].insert(ref: new_ref, name: 'A', tags: Sequel.pg_array(['ruby', 'js', 'react']))
      DB[:users].insert(ref: new_ref, name: 'B', tags: Sequel.pg_array(['ruby', 'python']))
      DB[:users].insert(ref: new_ref, name: 'C', tags: Sequel.pg_array(['ruby']))
    end

    it 'finds records with all matching tags' do
      _(User.dataset.where_all(['ruby', 'js'], :tags).count).must_equal 1
      _(User.dataset.where_all(['ruby', 'js'], :tags).first[:name]).must_equal 'A'
    end

    it 'works with single tag' do
      _(User.dataset.where_all('ruby', :tags).count).must_equal 3
    end

    it 'returns empty when no records match all tags' do
      _(User.dataset.where_all(['ruby', 'go'], :tags).count).must_equal 0
    end

    it 'returns self when data is blank' do
      _(User.dataset.where_all(nil, :tags).count).must_equal 3
      _(User.dataset.where_all('', :tags).count).must_equal 3
    end
  end
end

# =========================================================================
#  model_tree.rb
# =========================================================================

describe 'plugins/db/model_tree.rb (ModelTree)' do
  db_plugin_setup
  before { DB[:tree_nodes].delete }

  def root_ref;        @root_ref        ||= new_ref; end
  def child_ref;       @child_ref       ||= new_ref; end
  def grandchild_ref;  @grandchild_ref  ||= new_ref; end

  before do
    DB[:tree_nodes].insert(ref: root_ref, name: 'Root', parent_refs: Sequel.pg_array([], :text))
    DB[:tree_nodes].insert(ref: child_ref, name: 'Child', parent_refs: Sequel.pg_array([root_ref], :text))
    DB[:tree_nodes].insert(ref: grandchild_ref, name: 'Grandchild', parent_refs: Sequel.pg_array([child_ref, root_ref], :text))
  end

  describe '#parent' do
    it 'returns the direct parent (first element of parent_refs)' do
      child = TreeNode[child_ref]
      _(child.parent.ref).must_equal root_ref
    end
  end

  describe '#children' do
    it 'returns direct children' do
      root = TreeNode[root_ref]
      kids = root.children
      _(kids.map(&:ref)).must_include child_ref
    end
  end

  describe '#children_refs' do
    it 'returns self ref plus all descendant refs' do
      root = TreeNode[root_ref]
      refs = root.children_refs
      _(refs).must_include root_ref
      _(refs).must_include child_ref
      _(refs).must_include grandchild_ref
    end
  end

  describe '#parent_ref=' do
    it 'sets full ancestor chain in parent_refs' do
      new_node = TreeNode.new
      new_node[:ref] = new_ref
      new_node[:name] = 'New'
      new_node.parent_ref = child_ref
      _(new_node[:parent_refs]).must_include child_ref
      _(new_node[:parent_refs]).must_include root_ref
    end
  end
end

# =========================================================================
#  paginate.rb
# =========================================================================

describe 'plugins/db/paginate.rb' do
  db_plugin_setup
  before { DB[:users].delete }

  before do
    # truncate first - earlier `it`s in this describe (and earlier
    # describes) leave rows behind that throw off page-size math
    DB[:users].delete
    10.times do |i|
      DB[:users].insert(ref: new_ref, name: "P#{i.to_s.rjust(2, '0')}", created_at: Time.now.utc - (i * 60))
    end
  end

  # Paginate reads page from Lux.current.params[param], so we use a unique
  # param name and set it in the request URL to control pagination in tests.

  describe 'Paginate()' do
    it 'returns the requested page size' do
      result = Paginate(User.dataset.order(:name), size: 3, page: 1)
      _(result.length).must_equal 3
    end

    it 'paginates correctly across pages' do
      Lux::Current.new('http://test?pg=1')
      page1 = Paginate(User.dataset.order(:name), size: 4, param: :pg)
      Lux::Current.new('http://test?pg=2')
      page2 = Paginate(User.dataset.order(:name), size: 4, param: :pg)
      assert_empty(page1.map(&:name) & page2.map(&:name))
    end

    it 'sets paginate_page from request params' do
      Lux::Current.new('http://test?pg=3')
      result = Paginate(User.dataset, size: 5, param: :pg)
      _(result.paginate_page).must_equal 3
    end

    it 'sets paginate_next to true when more records exist' do
      result = Paginate(User.dataset.order(:name), size: 5, page: 1)
      _(result.paginate_next).must_equal true
    end

    it 'sets paginate_next to false on last page' do
      result = Paginate(User.dataset.order(:name), size: 20, page: 1)
      _(result.paginate_next).must_equal false
    end

    it 'sets paginate_opts' do
      Lux::Current.new('http://test?pg=2')
      result = Paginate(User.dataset, size: 5, param: :pg)
      opts = result.paginate_opts
      _(opts[:page]).must_equal 2
      _(opts[:param]).must_equal :pg
    end

    it 'defaults page to 1 for invalid values' do
      result = Paginate(User.dataset, size: 5, page: 0)
      _(result.paginate_page).must_equal 1
    end
  end

  describe 'dataset #page / #paginate' do
    it 'works as dataset method' do
      result = User.dataset.order(:name).page(size: 3, page: 1)
      _(result.length).must_equal 3
      assert_respond_to result, :paginate_next
    end

    it 'is aliased as #paginate' do
      result = User.dataset.order(:name).paginate(size: 3, page: 1)
      _(result.length).must_equal 3
    end
  end
end

# =========================================================================
#  link_objects.rb – plural ref (has_many)
# =========================================================================

describe 'plugins/db/link_objects.rb – plural ref' do
  db_plugin_setup
  before do
    DB[:users].delete
    DB[:tasks].delete
    DB[:comments].delete
    DB[:projects].delete
  end

  describe 'link :users (array-based has_many via user_refs[])' do
    def u1_ref; @u1_ref ||= new_ref; end
    def u2_ref; @u2_ref ||= new_ref; end

    before do
      DB[:users].insert(ref: u1_ref, name: 'Alice')
      DB[:users].insert(ref: u2_ref, name: 'Bob')
    end

    it 'returns associated models from the refs array' do
      p_ref = new_ref
      DB[:projects].insert(ref: p_ref, name: 'P1', user_refs: Sequel.pg_array([u1_ref, u2_ref]))
      project = Project[p_ref]

      users = project.users
      _(users.length).must_equal 2
      _(users.map(&:name).sort).must_equal ['Alice', 'Bob']
    end

    it 'returns empty array when refs array is empty' do
      p_ref = new_ref
      DB[:projects].insert(ref: p_ref, name: 'P2', user_refs: Sequel.pg_array([], :text))
      project = Project[p_ref]

      _(project.users).must_equal []
    end

    it 'returns empty array when refs is nil' do
      p_ref = new_ref
      DB[:projects].insert(ref: p_ref, name: 'P3')
      project = Project[p_ref]

      _(project.users).must_equal []
    end
  end

  describe 'link :comments (reverse-lookup has_many)' do
    def task_ref; @task_ref ||= new_ref; end

    before do
      DB[:tasks].insert(ref: task_ref, name: 'MyTask')
    end

    it 'returns a dataset of associated records via reverse FK' do
      DB[:comments].insert(ref: new_ref, body: 'C1', task_ref: task_ref)
      DB[:comments].insert(ref: new_ref, body: 'C2', task_ref: task_ref)
      DB[:comments].insert(ref: new_ref, body: 'Other', task_ref: 'other')

      task = Task[task_ref]
      comments = task.comments

      assert_respond_to comments, :count
      _(comments.count).must_equal 2
      _(comments.map(&:body).sort).must_equal ['C1', 'C2']
    end

    it 'returns empty dataset when no associated records exist' do
      task = Task[task_ref]
      _(task.comments.count).must_equal 0
    end
  end

  describe 'ref singular setter (belongs_to)' do
    it 'sets the ref column from an object' do
      u_ref = new_ref
      DB[:users].insert(ref: u_ref, name: 'Owner')
      user = User[u_ref]

      task = Task.new
      task[:ref] = new_ref
      task[:name] = 'T'
      task.user = user

      _(task[:user_ref]).must_equal u_ref
    end
  end

  describe 'where_ref via parent_type/parent_ref fallback' do
    def user_ref; @user_ref ||= new_ref; end
    def user
      @user ||= begin
        DB[:users].insert(ref: user_ref, name: 'Parent')
        User[user_ref]
      end
    end
    before { user }  # eager (was let!)

    it 'scopes by parent_type and parent_ref when no FK column exists' do
      DB[:notes].insert(ref: new_ref, body: 'N1', parent_type: 'User', parent_ref: user_ref)
      DB[:notes].insert(ref: new_ref, body: 'N2', parent_type: 'User', parent_ref: 'other')

      _(Note.where_ref(user).count).must_equal 1
      _(Note.where_ref(user).first.body).must_equal 'N1'
    end
  end
end

# =========================================================================
#  _parent_model.rb – parent_type + parent_ref style
# =========================================================================

describe 'plugins/db/_parent_model.rb – parent_type/parent_ref style' do
  db_plugin_setup
  before do
    DB[:users].delete
    DB[:notes].delete
  end

  def user_ref
    @user_ref ||= new_ref
  end

  def user
    @user ||= begin
      DB[:users].insert(ref: user_ref, name: 'Owner')
      User[user_ref]
    end
  end

  before { user }  # eager (was let!)

  describe '#parent= (parent_type/parent_ref)' do
    it 'sets parent_type and parent_ref from a model' do
      note = Note.new
      note[:ref] = new_ref
      note[:body] = 'Hello'
      note.parent = user

      _(note[:parent_type]).must_equal 'User'
      _(note[:parent_ref]).must_equal user_ref
    end
  end

  describe '#parent getter (parent_type/parent_ref)' do
    it 'retrieves parent from parent_type and parent_ref' do
      n_ref = new_ref
      DB[:notes].insert(ref: n_ref, body: 'Test', parent_type: 'User', parent_ref: user_ref)
      note = Note[n_ref]

      _(note.parent).must_be_kind_of User
      _(note.parent.ref).must_equal user_ref
    end

    it 'caches the parent after first access' do
      n_ref = new_ref
      DB[:notes].insert(ref: n_ref, body: 'Test', parent_type: 'User', parent_ref: user_ref)
      note = Note[n_ref]

      parent1 = note.parent
      parent2 = note.parent
      _(parent1.object_id).must_equal parent2.object_id
    end
  end

  describe '#parent with argument (chaining setter)' do
    it 'sets parent and returns self for chaining' do
      note = Note.new
      note[:ref] = new_ref
      result = note.parent(user)

      assert_same note, result
      _(note[:parent_type]).must_equal 'User'
      _(note[:parent_ref]).must_equal user_ref
    end
  end

  describe '#parent?' do
    it 'returns truthy for model with parent_type column' do
      note = Note.new
      assert note.parent?
    end
  end

  describe '.where_ref (parent_type/parent_ref)' do
    it 'scopes records to given parent' do
      DB[:notes].insert(ref: new_ref, body: 'N1', parent_type: 'User', parent_ref: user_ref)
      DB[:notes].insert(ref: new_ref, body: 'N2', parent_type: 'User', parent_ref: 'other')
      DB[:notes].insert(ref: new_ref, body: 'N3', parent_type: 'Task', parent_ref: user_ref)

      notes = Note.where_ref(user)
      _(notes.count).must_equal 1
      _(notes.first.body).must_equal 'N1'
    end
  end

  describe 'DatasetMethods#for (parent_type/parent_ref)' do
    it 'filters dataset by parent_type and parent_ref' do
      DB[:notes].insert(ref: new_ref, body: 'N1', parent_type: 'User', parent_ref: user_ref)
      DB[:notes].insert(ref: new_ref, body: 'N2', parent_type: 'Task', parent_ref: user_ref)

      result = Note.dataset.for(user)
      _(result.count).must_equal 1
      _(result.first.body).must_equal 'N1'
    end
  end
end

# =========================================================================
#  _ref_linker.rb - parent_model column (preferred over parent_type)
# =========================================================================

describe 'plugins/db/_ref_linker.rb - parent_model column' do
  db_plugin_setup
  before do
    DB[:users].delete
    DB[:memos].delete
    DB[:both_polys].delete
  end

  def user_ref
    @user_ref ||= new_ref
  end

  def user
    @user ||= begin
      DB[:users].insert(ref: user_ref, name: 'Owner')
      User[user_ref]
    end
  end

  before { user }  # eager (was let!)

  describe 'parent_model column on its own' do
    it 'writes parent_model and parent_ref from a model' do
      m = Memo.new
      m[:ref] = new_ref
      m.parent = user
      _(m[:parent_model]).must_equal 'User'
      _(m[:parent_ref]).must_equal user_ref
    end

    it 'reads parent through parent_model' do
      m_ref = new_ref
      DB[:memos].insert(ref: m_ref, body: 'Hi', parent_model: 'User', parent_ref: user_ref)
      m = Memo[m_ref]
      _(m.parent).must_be_kind_of User
      _(m.parent.ref).must_equal user_ref
    end

    it 'parent? returns true for models with parent_model' do
      assert Memo.new.parent?
    end

    it 'scope routes through parent_model column' do
      DB[:memos].insert(ref: new_ref, body: 'M1', parent_model: 'User', parent_ref: user_ref)
      DB[:memos].insert(ref: new_ref, body: 'M2', parent_model: 'User', parent_ref: 'other')
      _(Memo.where_ref(user).count).must_equal 1
    end

    it 'detect returns :poly_pair with parent_model as the type column' do
      shape = Sequel::Plugins::RefLinker.detect(Memo, User)
      _(shape[:kind]).must_equal :poly_pair
      _(shape[:columns]).must_equal [:parent_model, :parent_ref]
    end
  end

  describe 'precedence when both columns exist' do
    it 'prefers parent_model over parent_type on write' do
      b = BothPoly.new
      b[:ref] = new_ref
      b.parent = user
      _(b[:parent_model]).must_equal 'User'
      _(b[:parent_type]).must_be_nil
      _(b[:parent_ref]).must_equal user_ref
    end

    it 'prefers parent_model on detect' do
      shape = Sequel::Plugins::RefLinker.detect(BothPoly, User)
      _(shape[:columns].first).must_equal :parent_model
    end
  end

  describe 'missing polymorphic columns' do
    it 'Lux.shell.die fires naming the searched columns and the host class' do
      messages = nil
      # Override Lux.shell.die for this test only; restore via singleton class cleanup.
      orig = Lux.shell.singleton_class.method_defined?(:die) ? Lux.shell.method(:die) : nil
      Lux.shell.define_singleton_method(:die) { |msg| messages = Array(msg); raise(msg.inspect) }

      begin
        bare = BareModel.new
        bare[:ref] = new_ref
        err = _ { bare.parent = user }.must_raise RuntimeError
        _(err.message).must_match(/BareModel/)
        _(messages.join(' ')).must_include 'BareModel'
        _(messages.join(' ')).must_include 'parent_model'
        _(messages.join(' ')).must_include 'parent_type'
        _(messages.join(' ')).must_include 'parent_key'
      ensure
        Lux.shell.singleton_class.send(:remove_method, :die) if Lux.shell.singleton_class.method_defined?(:die)
      end
    end
  end
end

# =========================================================================
#  create_limit.rb
# =========================================================================

describe 'plugins/db/create_limit.rb' do
  db_plugin_setup
  before do
    DB[:notes].delete
    DB[:users].delete
  end

  def current_user
    @current_user ||= begin
      ref = new_ref
      DB[:users].insert(ref: ref, name: 'Creator')
      User[ref]
    end
  end

  describe 'ClassMethods' do
    it '.create_limit stores the limit configuration' do
      _(Note.cattr.create_limit_data).must_equal [3, 1.hour, nil]
    end
  end

  describe 'validate' do
    it 'raises when no user is logged in' do
      User.current = nil
      note = Note.new(ref: new_ref, body: 'Test')
      err = _ { note.save }.must_raise Lux::Error
      _(err.message).must_match(/log in/)
    end

    it 'allows creation when under the limit' do
      User.current = current_user
      note = Note.new(ref: new_ref, body: 'Test', creator_ref: current_user.ref)
      note.save  # should not raise
    end

    it 'skips check on existing records (update)' do
      User.current = current_user
      note = Note.create(ref: new_ref, body: 'Test', creator_ref: current_user.ref)
      note.update(body: 'Updated')  # should not raise
    end

    it 'skips check when model has no creator_ref column' do
      User.current = current_user
      # Comment has no creator_ref, so create_limit validation is skipped
      comment = Comment.new(ref: new_ref, body: 'Hi')
      comment.save  # should not raise
    end

    describe 'when over the limit' do
      before do
        User.current = current_user
        # Bypass the Lux.env.test? guard by overriding the singleton method.
        Lux.env.define_singleton_method(:test?) { false }
      end

      after do
        Lux.env.singleton_class.send(:remove_method, :test?) if Lux.env.singleton_class.method_defined?(:test?)
      end

      it 'adds a validation error when rate limit is exceeded' do
        3.times { |i| Note.create(ref: new_ref, body: "N#{i}", creator_ref: current_user.ref) }

        note = Note.new(ref: new_ref, body: 'One too many', creator_ref: current_user.ref)
        note.valid?

        _(note.errors[:base]).must_be_kind_of Array
        _(note.errors[:base].first).must_include 'max of 3'
        _(note.errors[:base].first).must_include 'Spam protection'
      end

      it 'does not block different users' do
        3.times { |i| Note.create(ref: new_ref, body: "N#{i}", creator_ref: current_user.ref) }

        other_ref = new_ref
        DB[:users].insert(ref: other_ref, name: 'Other')
        other_user = User[other_ref]
        User.current = other_user

        note = Note.new(ref: new_ref, body: 'From other', creator_ref: other_user.ref)
        _(note.valid?).must_equal true
      end
    end
  end

  # ---------------------------------------------------------------------------
  # AutoMigrate – type conversions
  # ---------------------------------------------------------------------------

  describe 'AutoMigrate type conversions' do
    def table_name
      :am_type_test
    end

    before do
      # Original before(:all): load auto_migrate once via constant guard.
      unless defined?(AutoMigrate)
        load File.expand_path('../../plugins/db/migrate/auto_migrate.rb', __dir__)
      end
      AutoMigrate.auto_confirm = true
      DB.drop_table?(table_name)
    end

    after do
      DB.drop_table?(:am_type_test)
      AutoMigrate.auto_confirm = false
    end

    def col_type field
      DB.schema(table_name).to_h[field][:db_type]
    end

    def run_migrate &block
      am = AutoMigrate.new(DB)
      am.table(table_name, &block)
      DB.schema(table_name, reload: true)
    end

    it 'converts string to integer' do
      DB.create_table(table_name) do
        String :ref, primary_key: true
        String :count
      end
      DB[table_name].insert(ref: 'r1', count: '42')

      run_migrate do |f|
        f.integer :count
      end

      _(col_type(:count)).must_equal 'integer'
      _(DB[table_name].first[:count]).must_equal 42
    end

    it 'converts string to boolean' do
      DB.create_table(table_name) do
        String :ref, primary_key: true
        String :active
      end
      DB[table_name].insert(ref: 'r1', active: 'true')
      DB[table_name].insert(ref: 'r2', active: 'no')

      run_migrate do |f|
        f.boolean :active
      end

      _(col_type(:active)).must_equal 'boolean'
      rows = DB[table_name].order(:ref).all
      _(rows[0][:active]).must_equal true
      _(rows[1][:active]).must_equal false
    end

    it 'converts integer to string' do
      DB.create_table(table_name) do
        String :ref, primary_key: true
        Integer :code
      end
      DB[table_name].insert(ref: 'r1', code: 123)

      run_migrate do |f|
        f.string :code, limit: 50
      end

      _(col_type(:code)).must_equal 'character varying(50)'
      _(DB[table_name].first[:code]).must_equal '123'
    end

    it 'converts integer to boolean' do
      DB.create_table(table_name) do
        String :ref, primary_key: true
        Integer :flag
      end
      DB[table_name].insert(ref: 'r1', flag: 1)
      DB[table_name].insert(ref: 'r2', flag: 0)

      run_migrate do |f|
        f.boolean :flag
      end

      _(col_type(:flag)).must_equal 'boolean'
      rows = DB[table_name].order(:ref).all
      _(rows[0][:flag]).must_equal true
      _(rows[1][:flag]).must_equal false
    end

    it 'converts boolean to integer' do
      DB.create_table(table_name) do
        String :ref, primary_key: true
        TrueClass :flag, default: false
      end
      DB[table_name].insert(ref: 'r1', flag: true)
      DB[table_name].insert(ref: 'r2', flag: false)

      run_migrate do |f|
        f.integer :flag
      end

      _(col_type(:flag)).must_equal 'integer'
      rows = DB[table_name].order(:ref).all
      _(rows[0][:flag]).must_equal 1
      _(rows[1][:flag]).must_equal 0
    end

    it 'converts decimal to integer (truncates)' do
      DB.create_table(table_name) do
        String :ref, primary_key: true
        BigDecimal :price, size: [8, 2]
      end
      DB[table_name].insert(ref: 'r1', price: 3.14)

      run_migrate do |f|
        f.integer :price
      end

      _(col_type(:price)).must_equal 'integer'
      _(DB[table_name].first[:price]).must_equal 3
    end

    it 'converts integer to decimal' do
      DB.create_table(table_name) do
        String :ref, primary_key: true
        Integer :amount
      end
      DB[table_name].insert(ref: 'r1', amount: 100)

      run_migrate do |f|
        f.decimal :amount
      end

      _(col_type(:amount)).must_include 'numeric'
      _(DB[table_name].first[:amount].to_f).must_equal 100.0
    end

    it 'converts string to date' do
      DB.create_table(table_name) do
        String :ref, primary_key: true
        String :born_on
      end
      DB[table_name].insert(ref: 'r1', born_on: '2025-06-15')

      run_migrate do |f|
        f.date :born_on
      end

      _(col_type(:born_on)).must_equal 'date'
      _(DB[table_name].first[:born_on]).must_equal Date.new(2025, 6, 15)
    end

    it 'converts string to timestamp' do
      DB.create_table(table_name) do
        String :ref, primary_key: true
        String :happened_at
      end
      DB[table_name].insert(ref: 'r1', happened_at: '2025-06-15 10:30:00')

      run_migrate do |f|
        f.datetime :happened_at
      end

      _(col_type(:happened_at)).must_include 'timestamp'
      _(DB[table_name].first[:happened_at]).must_be_kind_of Time
    end

    it 'converts date to timestamp' do
      DB.create_table(table_name) do
        String :ref, primary_key: true
        Date :started
      end
      DB[table_name].insert(ref: 'r1', started: Date.new(2025, 1, 1))

      run_migrate do |f|
        f.datetime :started
      end

      _(col_type(:started)).must_include 'timestamp'
    end

    it 'converts timestamp to date (truncates time)' do
      DB.create_table(table_name) do
        String :ref, primary_key: true
        DateTime :started
      end
      DB[table_name].insert(ref: 'r1', started: Time.new(2025, 6, 15, 14, 30, 0))

      run_migrate do |f|
        f.date :started
      end

      _(col_type(:started)).must_equal 'date'
      _(DB[table_name].first[:started]).must_equal Date.new(2025, 6, 15)
    end

    it 'converts string to decimal' do
      DB.create_table(table_name) do
        String :ref, primary_key: true
        String :price
      end
      DB[table_name].insert(ref: 'r1', price: '19.99')

      run_migrate do |f|
        f.decimal :price
      end

      _(col_type(:price)).must_include 'numeric'
      _(DB[table_name].first[:price].to_f).must_equal 19.99
    end

    it 'converts array base type (text[] to integer[])' do
      DB.create_table(table_name) do
        String :ref, primary_key: true
        column :ids, 'text[]', default: Sequel.lit("'{}'")
      end
      DB[table_name].insert(ref: 'r1', ids: Sequel.pg_array(['1', '2', '3']))

      run_migrate do |f|
        f.integer :ids, array: true
      end

      _(col_type(:ids)).must_equal 'integer[]'
      _(DB[table_name].first[:ids]).must_equal [1, 2, 3]
    end

    it 'prints warning for unknown conversion' do
      DB.create_table(table_name) do
        String :ref, primary_key: true
        TrueClass :flag, default: false
      end

      out = capture_stdout do
        run_migrate do |f|
          f.date :flag
        end
      end
      _(out).must_match(/Cannot auto-convert/)
    end
  end
end

# =========================================================================
#  schema_define.rb – `enum` DSL inside `schema do ... end`
# =========================================================================

describe 'plugins/db/schema_define.rb – enum DSL' do
  db_plugin_setup

  describe 'column synthesis' do
    it 'derives _sid column + max from longest string key' do
      rule = Lux.schema(:enum_widget).rules[:status_sid]
      _(rule[:type]).must_equal :string
      _(rule[:max]).must_equal 1
      _(rule[:default]).must_equal 'a'
      _(rule[:required]).must_equal true
      _(rule[:allowed]).must_equal [:a, :i, :d]
    end

    it 'derives _id column with integer type for numeric keys' do
      rule = Lux.schema(:enum_widget).rules[:level_id]
      _(rule[:type]).must_equal :integer
      _(rule[:allowed]).must_equal [1, 2, 3]
      refute rule.key?(:max)
    end

    it 'marks ? suffix fields as optional' do
      rule = Lux.schema(:enum_widget).rules[:mood_sid]
      _(rule[:required]).must_equal false
    end

    it 'merges user-supplied meta and auto-wires :collection' do
      rule = Lux.schema(:enum_widget).rules[:mood_sid]
      _(rule[:meta][:label]).must_equal 'Mood'
      _(rule[:meta][:collection]).must_be_kind_of Proc
    end
  end

  describe 'plugin replay (class + instance helpers)' do
    it 'defines pluralized class accessor returning values hash' do
      _(EnumWidget.statuses).must_be_kind_of Hash
      _(EnumWidget.statuses).must_equal({ 'a' => 'Active', 'i' => 'Inactive', 'd' => 'Disabled' }.to_lux_hash)
      _(EnumWidget.statuses('i')).must_equal 'Inactive'
    end

    it 'defines class accessor for integer-keyed enums' do
      # Lux::Hash stringifies all keys; integer lookups still resolve
      # (1 → "1") so callers keep using `levels[2]` verbatim.
      _(EnumWidget.levels.keys).must_equal ['1', '2', '3']
      _(EnumWidget.levels(2)).must_equal 'Normal'
      _(EnumWidget.levels('2')).must_equal 'Normal'
    end

    it 'defines instance label method' do
      DB[:enum_widgets].delete
      DB[:enum_widgets].insert(ref: new_ref, status_sid: 'i', level_id: 3, mood_sid: 'h')
      w = EnumWidget.first
      _(w.status).must_equal 'Inactive'
      _(w.level).must_equal 'High'
      _(w.mood).must_equal 'Happy'
    end

    it 'auto-wires meta[:collection] to Klass.<plural>' do
      rule  = Lux.schema(:enum_widget).rules[:status_sid]
      proc_ = rule[:meta][:collection]
      result = EnumWidget.new.instance_exec(&proc_)
      _(result).must_equal EnumWidget.statuses
    end
  end

  describe 'schema-level rejection of unknown values' do
    it 'rejects via :allowed before enums_plugin save validation' do
      DB[:enum_widgets].delete
      w = EnumWidget.new
      w[:ref] = new_ref
      w[:status_sid] = 'zz'
      w[:level_id] = 1
      _(w.valid?).must_equal false
      _(w.errors[:status_sid].join).must_match(/not allowed/)
    end
  end

  describe 'die-early checks' do
    before do
      # die normally exits the process; raise instead so we can assert on it.
      Lux.shell.define_singleton_method(:die) { |msg| raise(msg) }
    end

    after do
      Lux.shell.singleton_class.send(:remove_method, :die) if Lux.shell.singleton_class.method_defined?(:die)
    end

    it 'dies when neither block nor values: is given' do
      err = _ { Lux.schema { enum :foo } }.must_raise RuntimeError
      _(err.message).must_match(/no values given/)
    end

    it 'dies when default is not in keys' do
      err = _ {
        Lux.schema do
          enum :foo, default: 'x' do |f|
            f[:a] = 'A'
          end
        end
      }.must_raise RuntimeError
      _(err.message).must_match(/default "x" not in keys/)
    end

    it 'dies on mixed key types' do
      err = _ {
        Lux.schema do
          enum :foo do |f|
            f[1] = 'A'
            f[:b] = 'B'
          end
        end
      }.must_raise RuntimeError
      _(err.message).must_match(/mixed key types/)
    end

    it 'dies on duplicate column declaration' do
      err = _ {
        Lux.schema do
          status_sid max: 1
          enum :status do |f|
            f[:a] = 'A'
          end
        end
      }.must_raise RuntimeError
      _(err.message).must_match(/column :status_sid already declared/)
    end
  end
end
