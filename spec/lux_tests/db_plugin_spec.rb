require 'spec_helper'

# ---------------------------------------------------------------------------
# Database bootstrap – standalone test DB so we never touch real data
# ---------------------------------------------------------------------------

DB = Sequel.connect('postgres:///lux_fw_test') unless defined?(DB)
DB.extension :pg_array
Sequel.extension :pg_array_ops

# Silence Sequel logger during tests
DB.loggers.clear

# Enable dirty tracking (needed for on_change)
Sequel::Model.plugin :dirty

# ---------------------------------------------------------------------------
# Load all DB plugins under test
# ---------------------------------------------------------------------------

plugin_dir = File.expand_path('../../plugins/db', __dir__)

# core + dataset_methods first (others may rely on them)
load File.join(plugin_dir, 'core.rb')
load File.join(plugin_dir, 'dataset_methods.rb')
load File.join(plugin_dir, 'find_precache.rb')
load File.join(plugin_dir, 'before_save_filters.rb')
load File.join(plugin_dir, 'enums_plugin.rb')
load File.join(plugin_dir, 'hooks.rb')
load File.join(plugin_dir, '_parent_model.rb')
load File.join(plugin_dir, 'link_objects.rb')
load File.join(plugin_dir, 'composite_primary_keys.rb')
load File.join(plugin_dir, 'array_search.rb')
load File.join(plugin_dir, 'paginate.rb')
load File.join(plugin_dir, 'model_tree.rb')
load File.join(plugin_dir, 'create_limit.rb')

# Register Sequel plugins so models can use `plugin :name`
Sequel::Model.plugin :parent_model
Sequel::Model.plugin :lux_links
Sequel::Model.plugin :primary_keys
Sequel::Model.plugin :lux_hooks
Sequel::Model.plugin :lux_before_save
Sequel::Model.plugin :lux_create_limit

# ---------------------------------------------------------------------------
# Schema – create test tables fresh every run
# ---------------------------------------------------------------------------

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

  enums :steps, values: { 'a' => 'Active', 'i' => 'Inactive', 'd' => 'Disabled' }
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

# Add plural reverse-lookup link after both classes exist
Comment.scope(:default) { self }
Task.plugin :lux_links
Task.class_eval { link :comments }

# Singular link setter was untested - Task already has `link :user`

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def new_ref
  Crypt.uid(12)
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
# Scoped via metadata so we don't pollute other spec files.
RSpec.configure do |c|
  c.before(:each, :db_plugin) do
    Lux::Current.new('http://test')
    User.current = nil
  end
end

# =========================================================================
#  core.rb
# =========================================================================

describe 'plugins/db/core.rb', :db_plugin do
  before(:each) { DB[:users].delete }

  # -- ClassMethods --------------------------------------------------------

  describe 'Sequel::Model ClassMethods' do
    describe '.find_by' do
      it 'returns the first matching record' do
        ref = new_ref
        DB[:users].insert(ref: ref, name: 'Alice')
        user = User.find_by(name: 'Alice')
        expect(user).to be_a(User)
        expect(user.ref).to eq(ref)
      end

      it 'returns nil when nothing matches' do
        expect(User.find_by(name: 'Ghost')).to be_nil
      end
    end

    describe '.scope' do
      before do
        User.scope(:named) { where(Sequel.lit("name is not null and name != ''")) }
      end

      it 'defines a dataset method usable as a chainable scope' do
        DB[:users].insert(ref: new_ref, name: 'Alice')
        DB[:users].insert(ref: new_ref, name: '')
        expect(User.named.count).to eq(1)
      end
    end

    describe '.first_or_new' do
      it 'returns existing record if found' do
        ref = new_ref
        DB[:users].insert(ref: ref, name: 'Bob')
        user = User.first_or_new(ref: ref)
        expect(user.name).to eq('Bob')
        expect(user.new?).to be false
      end

      it 'returns a new unsaved record if not found' do
        user = User.first_or_new(name: 'Charlie')
        expect(user.new?).to be true
        expect(user.name).to eq('Charlie')
      end

      it 'yields block when object has no :id column value' do
        # Sequel#id returns @values[:id], which is nil for ref-based PKs,
        # so the block is yielded for both new and existing records.
        yielded = false
        User.first_or_new(name: 'Charlie') { |u| yielded = true }
        expect(yielded).to be true
      end
    end

    describe '.first_or_create' do
      it 'creates a new record if not found' do
        user = User.first_or_create(name: 'Dave') { |u| u.ref ||= new_ref }
        expect(user.new?).to be false
        expect(User.where(name: 'Dave').count).to eq(1)
      end

      it 'returns existing record if found' do
        ref = new_ref
        DB[:users].insert(ref: ref, name: 'Eve')
        user = User.first_or_create(name: 'Eve')
        expect(user.ref).to eq(ref)
      end
    end
  end

  # -- InstanceMethods -----------------------------------------------------

  describe 'Sequel::Model InstanceMethods' do
    let(:ref) { new_ref }
    let!(:user) do
      DB[:users].insert(ref: ref, name: 'Alice', email: 'a@b.c', age: 30, updated_at: Time.now.utc)
      User[ref]
    end

    describe '#key' do
      it 'returns Class/ref format' do
        expect(user.key).to eq("User/#{ref}")
      end

      it 'appends namespace when given' do
        expect(user.key(:notes)).to eq("User/#{ref}/notes")
      end
    end

    describe '#cache_key' do
      it 'includes id and updated_at timestamp when available' do
        ck = user.cache_key
        expect(ck).to include("User/")
        expect(ck).to include(user.id.to_s)
        expect(ck).to match(/-[\d.]+$/)
      end

      it 'appends namespace' do
        expect(user.cache_key(:v2)).to match(%r{/v2$})
      end

      it 'falls back to #key when no updated_at' do
        DB[:comments].insert(ref: 'c1', body: 'hi')
        comment = Comment['c1']
        expect(comment.cache_key).to eq(comment.key)
      end
    end

    describe '#attributes / #to_h' do
      it 'returns a hash of all column values as strings keys' do
        h = user.attributes
        expect(h).to be_a(Hash)
        expect(h['name']).to eq('Alice')
        expect(h['ref']).to eq(ref)
      end

      it 'is aliased as to_h' do
        expect(user.to_h).to eq(user.attributes)
      end
    end

    describe '#has?' do
      it 'returns true when field is present' do
        expect(user.has?(:name)).to be true
      end

      it 'returns false when field is blank' do
        user[:name] = nil
        expect(user.has?(:name)).to be false
      end

      it 'adds error and returns false with message string' do
        user[:email] = nil
        result = user.has?(:email, 'Email is required')
        expect(result).to be false
        expect(user.errors[:email]).to include('Email is required')
      end

      it 'returns true and adds no error when present with message' do
        result = user.has?(:name, 'Name required')
        expect(result).to be true
        expect(user.errors).to be_empty
      end
    end

    describe '#unique?' do
      it 'returns true when no other record has same value' do
        expect(user.unique?(:email)).to be true
      end

      it 'returns false when another record shares the value' do
        DB[:users].insert(ref: new_ref, name: 'Alice', email: 'a@b.c')
        expect(user.unique?(:email)).to be false
      end
    end

    describe '#save!' do
      it 'saves without validation' do
        u = User.new
        u[:ref] = new_ref
        u[:name] = 'NoVal'
        expect { u.save! }.not_to raise_error
        expect(User.where(name: 'NoVal').count).to eq(1)
      end
    end

    describe '#slice' do
      it 'returns a hash of requested fields' do
        h = user.slice(:name, :email)
        expect(h).to eq({ name: 'Alice', email: 'a@b.c' })
      end
    end

    describe '#merge' do
      it 'sets attributes from hash' do
        user.merge(name: 'Bob', email: 'b@c.d')
        expect(user.name).to eq('Bob')
        expect(user.email).to eq('b@c.d')
      end

      it 'ignores unknown keys' do
        expect { user.merge(nonexistent_field: 'x') }.not_to raise_error
      end
    end

    describe '#on_change' do
      # -- Primitives: replace, add, remove ---------------------------------

      it 'yields previous and new values when string replaced' do
        user.name = 'Zara'
        yielded = nil
        user.on_change(:name) { |prev, cur| yielded = [prev, cur] }
        expect(yielded).to eq(['Alice', 'Zara'])
      end

      it 'yields when value added (nil -> value)' do
        # create user with nil email
        r = new_ref
        DB[:users].insert(ref: r, name: 'NoEmail', email: nil)
        u = User[r]

        u.email = 'new@test.com'
        yielded = nil
        u.on_change(:email) { |prev, cur| yielded = [prev, cur] }
        expect(yielded).to eq([nil, 'new@test.com'])
      end

      it 'yields when value removed (value -> nil)' do
        user.name = nil
        yielded = nil
        user.on_change(:name) { |prev, cur| yielded = [prev, cur] }
        expect(yielded).to eq(['Alice', nil])
      end

      it 'yields when integer replaced' do
        user.age = 40
        yielded = nil
        user.on_change(:age) { |prev, cur| yielded = [prev, cur] }
        expect(yielded).to eq([30, 40])
      end

      it 'yields when boolean replaced' do
        user.is_active = false
        yielded = nil
        user.on_change(:is_active) { |prev, cur| yielded = [prev, cur] }
        expect(yielded).to eq([true, false])
      end

      it 'does not yield when column unchanged' do
        yielded = false
        user.on_change(:name) { yielded = true }
        expect(yielded).to be false
      end

      # -- Arrays: add, remove, replace, set, clear --------------------------

      it 'yields when array element added' do
        r = new_ref
        DB[:users].insert(ref: r, name: 'Tagged', tags: Sequel.pg_array(['ruby']))
        u = User[r]

        u.tags = Sequel.pg_array(['ruby', 'js'])
        yielded = nil
        u.on_change(:tags) { |prev, cur| yielded = [prev, cur] }
        expect(yielded[0]).to eq(['ruby'])
        expect(yielded[1]).to eq(['ruby', 'js'])
      end

      it 'yields when array element removed' do
        r = new_ref
        DB[:users].insert(ref: r, name: 'Tagged', tags: Sequel.pg_array(['ruby', 'js']))
        u = User[r]

        u.tags = Sequel.pg_array(['ruby'])
        yielded = nil
        u.on_change(:tags) { |prev, cur| yielded = [prev, cur] }
        expect(yielded[0]).to eq(['ruby', 'js'])
        expect(yielded[1]).to eq(['ruby'])
      end

      it 'yields when array element replaced' do
        r = new_ref
        DB[:users].insert(ref: r, name: 'Tagged', tags: Sequel.pg_array(['ruby']))
        u = User[r]

        u.tags = Sequel.pg_array(['go'])
        yielded = nil
        u.on_change(:tags) { |prev, cur| yielded = [prev, cur] }
        expect(yielded[0]).to eq(['ruby'])
        expect(yielded[1]).to eq(['go'])
      end

      it 'yields when array set from empty' do
        r = new_ref
        DB[:users].insert(ref: r, name: 'Empty', tags: Sequel.pg_array([], :text))
        u = User[r]

        u.tags = Sequel.pg_array(['ruby'])
        yielded = nil
        u.on_change(:tags) { |prev, cur| yielded = [prev, cur] }
        expect(yielded[0]).to eq([])
        expect(yielded[1]).to eq(['ruby'])
      end

      it 'yields when array cleared' do
        r = new_ref
        DB[:users].insert(ref: r, name: 'Tagged', tags: Sequel.pg_array(['ruby']))
        u = User[r]

        u.tags = Sequel.pg_array([], :text)
        yielded = nil
        u.on_change(:tags) { |prev, cur| yielded = [prev, cur] }
        expect(yielded[0]).to eq(['ruby'])
        expect(yielded[1]).to eq([])
      end

      it 'does not yield when array unchanged' do
        r = new_ref
        DB[:users].insert(ref: r, name: 'Tagged', tags: Sequel.pg_array(['ruby']))
        u = User[r]

        yielded = false
        u.on_change(:tags) { yielded = true }
        expect(yielded).to be false
      end

      # -- Multiple fields ---------------------------------------------------

      it 'yields independently for each changed field' do
        user.name = 'Bob'
        user.age = 99

        name_change = nil
        age_change = nil
        user.on_change(:name) { |prev, cur| name_change = [prev, cur] }
        user.on_change(:age) { |prev, cur| age_change = [prev, cur] }

        expect(name_change).to eq(['Alice', 'Bob'])
        expect(age_change).to eq([30, 99])
      end

      it 'does not yield for unchanged field when other fields changed' do
        user.name = 'Bob'

        yielded = false
        user.on_change(:age) { yielded = true }
        expect(yielded).to be false
      end
    end
  end

  # -- DatasetMethods (in core.rb) -----------------------------------------

  describe 'Sequel::Model DatasetMethods (core)' do
    before(:each) do
      DB[:users].delete
      3.times { |i| DB[:users].insert(ref: new_ref, name: "U#{i}", updated_at: Time.now.utc - (i * 60)) }
    end

    describe '.refs' do
      it 'returns array of ref strings' do
        result = User.dataset.refs
        expect(result).to be_an(Array)
        expect(result.length).to eq(3)
        result.each { |r| expect(r).to be_a(String) }
      end

      it 'respects limit' do
        expect(User.dataset.refs(2).length).to eq(2)
      end
    end

    describe '.latest' do
      it 'orders by updated_at descending' do
        times = User.dataset.latest.select_map(:updated_at)
        times.each_cons(2) { |a, b| expect(a).to be >= b }
      end
    end
  end
end

# =========================================================================
#  dataset_methods.rb
# =========================================================================

describe 'plugins/db/dataset_methods.rb', :db_plugin do
  before(:each) do
    DB[:users].delete
    DB[:tasks].delete
  end

  describe '.random' do
    it 'returns records in non-deterministic order without error' do
      3.times { |i| DB[:users].insert(ref: new_ref, name: "R#{i}") }
      expect(User.dataset.random.all.length).to eq(3)
    end
  end

  describe '.xwhere' do
    before do
      DB[:users].insert(ref: new_ref, name: 'Alice', age: 25)
      DB[:users].insert(ref: new_ref, name: 'Bob', age: 30)
      DB[:users].insert(ref: new_ref, name: '', age: 0)
    end

    it 'returns self when given nil' do
      expect(User.dataset.xwhere(nil).count).to eq(3)
    end

    it 'handles symbol to check non-blank' do
      # coalesce(name,'')!=''
      expect(User.dataset.xwhere(:name).count).to eq(2)
    end

    it 'handles raw SQL string' do
      expect(User.dataset.xwhere('age > ?', 26).count).to eq(1)
    end

    it 'handles hash conditions with present values' do
      expect(User.dataset.xwhere(name: 'Alice').count).to eq(1)
    end

    it 'filters out blank hash values' do
      # blank values are removed from hash conditions
      expect(User.dataset.xwhere(name: '').count).to eq(3)
    end

    context 'with postgres arrays' do
      before do
        DB[:users].delete
        DB[:users].insert(ref: new_ref, name: 'Tagged', tags: Sequel.pg_array(['ruby', 'js']))
      end

      it 'searches for single element in array column' do
        expect(User.dataset.xwhere(tags: 'ruby').count).to eq(1)
      end

      it 'searches for multiple elements with join type' do
        expect(User.dataset.xwhere({ tags: ['ruby', 'js'] }, 'and').count).to eq(1)
        expect(User.dataset.xwhere({ tags: ['ruby', 'python'] }, 'or').count).to eq(1)
      end
    end
  end

  describe '.xlike' do
    before do
      DB[:users].insert(ref: new_ref, name: 'Alice Smith')
      DB[:users].insert(ref: new_ref, name: 'Bob Jones')
    end

    it 'performs case-insensitive search' do
      expect(User.dataset.xlike('alice', :name).count).to eq(1)
    end

    it 'searches across multiple fields' do
      DB[:users].insert(ref: new_ref, name: 'Charlie', email: 'charlie@test.com')
      expect(User.dataset.xlike('charlie', :name, :email).count).to eq(1)
    end

    it 'handles multi-word search (AND logic between words)' do
      expect(User.dataset.xlike('alice smith', :name).count).to eq(1)
      expect(User.dataset.xlike('alice jones', :name).count).to eq(0)
    end

    it 'returns self for blank search' do
      expect(User.dataset.xlike('', :name).count).to eq(2)
      expect(User.dataset.xlike(nil, :name).count).to eq(2)
    end

    it 'raises for unknown fields' do
      expect { User.dataset.xlike('x', :nonexistent_column).all }.to raise_error(ArgumentError, /not found/)
    end
  end

  describe '.last_updated' do
    it 'returns the most recently updated record' do
      old_ref = new_ref
      new_r = new_ref
      DB[:users].insert(ref: old_ref, name: 'Old', updated_at: Time.now.utc - 3600)
      DB[:users].insert(ref: new_r, name: 'New', updated_at: Time.now.utc)
      expect(User.dataset.last_updated.ref).to eq(new_r)
    end

    it 'applies optional filter' do
      DB[:users].insert(ref: new_ref, name: 'A', age: 1, updated_at: Time.now.utc)
      DB[:users].insert(ref: new_ref, name: 'B', age: 2, updated_at: Time.now.utc - 100)
      expect(User.dataset.last_updated(age: 2).name).to eq('B')
    end
  end

  describe '.for' do
    it 'scopes by foreign ref field' do
      u_ref = new_ref
      DB[:users].insert(ref: u_ref, name: 'Alice')
      DB[:tasks].insert(ref: new_ref, name: 'T1', user_ref: u_ref)
      DB[:tasks].insert(ref: new_ref, name: 'T2', user_ref: 'other')

      user = User[u_ref]
      expect(Task.dataset.for(user).count).to eq(1)
      expect(Task.dataset.for(user).first.name).to eq('T1')
    end
  end

  describe '.desc / .asc' do
    before do
      DB[:users].insert(ref: new_ref, name: 'A', created_at: Time.now.utc - 200)
      DB[:users].insert(ref: new_ref, name: 'B', created_at: Time.now.utc - 100)
      DB[:users].insert(ref: new_ref, name: 'C', created_at: Time.now.utc)
    end

    it '.desc orders newest first by default' do
      expect(User.dataset.desc.first.name).to eq('C')
    end

    it '.desc accepts custom field' do
      expect(User.dataset.desc(:name).first.name).to eq('C')
    end

    it '.asc orders oldest first' do
      expect(User.dataset.asc.first.name).to eq('A')
    end
  end

  describe '.pluck' do
    it 'returns array of single field values' do
      DB[:users].insert(ref: new_ref, name: 'X')
      DB[:users].insert(ref: new_ref, name: 'Y')
      names = User.dataset.pluck(:name)
      expect(names).to contain_exactly('X', 'Y')
    end
  end

  describe '.ids' do
    it 'returns array of refs by default' do
      r1, r2 = new_ref, new_ref
      DB[:users].insert(ref: r1, name: 'A')
      DB[:users].insert(ref: r2, name: 'B')
      result = User.dataset.ids
      expect(result).to include(r1, r2)
    end

    it 'returns distinct values for a given field' do
      DB[:users].insert(ref: new_ref, name: 'A', age: 10)
      DB[:users].insert(ref: new_ref, name: 'B', age: 10)
      DB[:users].insert(ref: new_ref, name: 'C', age: 20)
      ages = User.dataset.ids(:age)
      expect(ages.uniq.sort).to eq([10, 20])
    end

    it 'provides a fallback element when empty' do
      result = User.dataset.ids
      # should have at least one element (fallback)
      expect(result.length).to be >= 1
    end
  end

  describe '.last' do
    before do
      DB[:users].insert(ref: new_ref, name: 'A', created_at: Time.now.utc - 200)
      DB[:users].insert(ref: new_ref, name: 'B', created_at: Time.now.utc - 100)
      DB[:users].insert(ref: new_ref, name: 'C', created_at: Time.now.utc)
    end

    it 'returns single most recent record without argument' do
      expect(User.dataset.last.name).to eq('C')
    end

    it 'returns array of N records with argument' do
      result = User.dataset.last(2)
      expect(result.length).to eq(2)
      expect(result.first.name).to eq('C')
    end
  end
end

# =========================================================================
#  find_precache.rb
# =========================================================================

describe 'plugins/db/find_precache.rb', :db_plugin do
  before(:each) { DB[:users].delete }

  let(:ref) { new_ref }

  before do
    DB[:users].insert(ref: ref, name: 'Cached')
  end

  describe '.find' do
    it 'returns the record by ref' do
      user = User.find(ref)
      expect(user).to be_a(User)
      expect(user.name).to eq('Cached')
    end

    it 'raises when not found' do
      expect { User.find('nonexistent') }.to raise_error(Sequel::Error, /not found/)
    end

    it 'returns nil for blank id' do
      expect(User.find(nil)).to be_nil
      expect(User.find('')).to be_nil
    end

    it 'caches within the same request scope' do
      user1 = User.find(ref)
      user2 = User.find(ref)
      expect(user1.object_id).to eq(user2.object_id)
    end
  end

  describe '.take' do
    it 'returns the record when found' do
      expect(User.take(ref).name).to eq('Cached')
    end

    it 'returns nil instead of raising when not found' do
      expect(User.take('nonexistent')).to be_nil
    end
  end
end

# =========================================================================
#  before_save_filters.rb
# =========================================================================

describe 'plugins/db/before_save_filters.rb', :db_plugin do
  before(:each) do
    DB[:users].delete
    User.current = nil
  end

  describe 'timestamp handling' do
    it 'sets created_at on new records' do
      u = create_user(name: 'New')
      expect(u.created_at).not_to be_nil
      expect(u.created_at).to be_within(2).of(Time.now.utc)
    end

    it 'sets updated_at on every save' do
      u = create_user(name: 'Up')
      original_updated = u.updated_at
      sleep 0.01
      u.update(name: 'Updated')
      expect(u.updated_at).to be > original_updated
    end
  end

  describe 'audit columns' do
    let(:current_user) do
      ref = new_ref
      DB[:users].insert(ref: ref, name: 'Admin')
      User[ref]
    end

    it 'sets creator_ref on create when user is logged in' do
      User.current = current_user
      u = create_user(name: 'Created')
      expect(u.creator_ref).to eq(current_user.ref)
    end

    it 'sets updater_ref on save when user is logged in' do
      User.current = current_user
      u = create_user(name: 'A')
      expect(u.updater_ref).to eq(current_user.ref)
    end

    it 'leaves audit columns nil when no current user' do
      User.current = nil
      u = create_user(name: 'NoAudit')
      expect(u.creator_ref).to be_nil
    end
  end

  describe 'soft delete' do
    it 'sets is_deleted instead of destroying when is_deleted column exists' do
      u = create_user(name: 'SoftDel')
      u.destroy
      row = DB[:users].where(ref: u.ref).first
      expect(row).not_to be_nil
      expect(row[:is_deleted]).to be true
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
      expect(names).to include('Active', 'Inactive')
      expect(names).not_to include('Deleted')
    end

    it '.deleted returns only soft-deleted records' do
      names = User.dataset.deleted.select_map(:name)
      expect(names).to eq(['Deleted'])
    end

    it '.activated returns only active records' do
      names = User.dataset.activated.select_map(:name)
      expect(names).to include('Active')
      expect(names).not_to include('Inactive')
    end

    it '.deactivated returns only inactive records' do
      names = User.dataset.deactivated.select_map(:name)
      expect(names).to eq(['Inactive'])
    end
  end
end

# =========================================================================
#  enums_plugin.rb
# =========================================================================

describe 'plugins/db/enums_plugin.rb', :db_plugin do
  before(:each) { DB[:users].delete }

  # User already has: enums :steps, values: { 'a'=>'Active', 'i'=>'Inactive', 'd'=>'Disabled' }

  describe '.enums class method' do
    it 'defines a class method returning all values' do
      expect(User.steps).to eq({ 'a' => 'Active', 'i' => 'Inactive', 'd' => 'Disabled' }.to_hwia)
    end

    it 'returns single value when called with id' do
      expect(User.steps('a')).to eq('Active')
      expect(User.steps('d')).to eq('Disabled')
    end
  end

  describe 'instance enum methods' do
    let(:user) do
      DB[:users].insert(ref: new_ref, name: 'EnumUser', step_sid: 'i')
      User.where(name: 'EnumUser').first
    end

    it '#step_sid returns the stored value or default' do
      expect(user.step_sid).to eq('i')
    end

    it '#step returns the human name' do
      expect(user.step).to eq('Inactive')
    end

    it 'returns default when field is blank' do
      DB[:users].insert(ref: new_ref, name: 'Default', step_sid: nil)
      u = User.where(name: 'Default').first
      expect(u.step_sid).to eq('a') # default
      expect(u.step).to eq('Active')
    end
  end

  describe 'array-based enums' do
    before do
      User.enums :priorities, ['low', 'medium', 'high']
    end

    it 'creates the class method with all keys' do
      vals = User.priorities
      expect(vals.keys).to contain_exactly('low', 'medium', 'high')
    end

    it 'returns nil values (array enums store key only)' do
      # array-based enums produce { 'low' => nil, 'medium' => nil, 'high' => nil }
      # because Array elements destructure as (key, nil) pairs
      expect(User.priorities['low']).to be_nil
    end

    it 'has no field (field: false for array-based)' do
      # no field defined, so only the class-level lookup is created
      expect(User.priorities).to respond_to(:keys)
    end
  end
end

# =========================================================================
#  hooks.rb
# =========================================================================

describe 'plugins/db/hooks.rb', :db_plugin do
  before(:each) { DB[:tasks].delete }

  describe 'before/after hooks' do
    it 'fires before(:c) on create' do
      fired = []
      Task.before(:c) { fired << :before_create }
      create_task(name: 'Hook')
      expect(fired).to include(:before_create)
    end

    it 'fires after(:c) on create' do
      fired = []
      Task.after(:c) { fired << :after_create }
      create_task(name: 'Hook')
      expect(fired).to include(:after_create)
    end

    it 'fires before(:u) on update' do
      fired = []
      Task.before(:u) { fired << :before_update }
      t = create_task(name: 'Hook')
      t.update(name: 'Updated')
      expect(fired).to include(:before_update)
    end

    it 'fires after(:u) on update' do
      fired = []
      Task.after(:u) { fired << :after_update }
      t = create_task(name: 'Hook')
      t.update(name: 'Updated')
      expect(fired).to include(:after_update)
    end

    it 'fires before(:d) on destroy' do
      fired = []
      Task.before(:d) { fired << :before_destroy }
      t = create_task(name: 'Hook')
      t.destroy
      expect(fired).to include(:before_destroy)
    end

    it 'fires after(:d) on destroy' do
      fired = []
      Task.after(:d) { fired << :after_destroy }
      t = create_task(name: 'Hook')
      t.destroy
      expect(fired).to include(:after_destroy)
    end

    it 'supports combined hooks like before(:cu)' do
      fired = []
      Task.before(:cu) { fired << :before_cu }
      create_task(name: 'A')
      expect(fired.count(:before_cu)).to eq(1) # create

      t = create_task(name: 'B')
      fired.clear
      t.update(name: 'C')
      expect(fired.count(:before_cu)).to eq(1) # update
    end
  end
end

# =========================================================================
#  _parent_model.rb
# =========================================================================

describe 'plugins/db/_parent_model.rb', :db_plugin do
  before(:each) do
    DB[:users].delete
    DB[:tasks].delete
  end

  let(:user_ref) { new_ref }
  let!(:user) do
    DB[:users].insert(ref: user_ref, name: 'Parent')
    User[user_ref]
  end

  describe '#parent= and #parent (parent_key style)' do
    it 'sets parent via parent_key' do
      t = Task.new
      t[:ref] = new_ref
      t[:name] = 'T'
      t.parent = user
      expect(t[:parent_key]).to eq("User/#{user_ref}")
    end

    it 'retrieves parent from parent_key' do
      t_ref = new_ref
      DB[:tasks].insert(ref: t_ref, name: 'T', parent_key: "User/#{user_ref}")
      t = Task[t_ref]
      expect(t.parent).to be_a(User)
      expect(t.parent.ref).to eq(user_ref)
    end

    it 'accepts a string key in Class/ref format' do
      t = Task.new
      t[:ref] = new_ref
      t.parent = "User/#{user_ref}"
      expect(t[:parent_key]).to eq("User/#{user_ref}")
    end
  end

  describe '#parent?' do
    it 'returns truthy when parent columns exist' do
      t = Task.new
      expect(t.parent?).to be_truthy
    end
  end

  describe '.for_parent' do
    it 'scopes records to given parent' do
      DB[:tasks].insert(ref: new_ref, name: 'T1', parent_key: "User/#{user_ref}")
      DB[:tasks].insert(ref: new_ref, name: 'T2', parent_key: 'User/other')

      tasks = Task.for_parent(user)
      expect(tasks.count).to eq(1)
      expect(tasks.first.name).to eq('T1')
    end
  end

  describe 'DatasetMethods#where_parent' do
    it 'filters dataset by parent' do
      DB[:tasks].insert(ref: new_ref, name: 'T1', parent_key: "User/#{user_ref}")
      DB[:tasks].insert(ref: new_ref, name: 'T2', parent_key: 'User/other')

      expect(Task.dataset.where_parent(user).count).to eq(1)
    end
  end
end

# =========================================================================
#  link_objects.rb
# =========================================================================

describe 'plugins/db/link_objects.rb', :db_plugin do
  before(:each) do
    DB[:users].delete
    DB[:tasks].delete
  end

  let(:user_ref) { new_ref }
  let!(:user) do
    DB[:users].insert(ref: user_ref, name: 'Owner')
    User[user_ref]
  end

  describe 'DatasetMethods#where_ref' do
    it 'scopes by foreign ref column' do
      DB[:tasks].insert(ref: new_ref, name: 'T1', user_ref: user_ref)
      DB[:tasks].insert(ref: new_ref, name: 'T2', user_ref: 'other')

      expect(Task.dataset.where_ref(user).count).to eq(1)
    end

    it 'returns self when object is nil' do
      DB[:tasks].insert(ref: new_ref, name: 'T1')
      expect(Task.dataset.where_ref(nil).count).to eq(1)
    end
  end

  describe 'ClassMethods.where_ref' do
    it 'delegates to dataset' do
      DB[:tasks].insert(ref: new_ref, name: 'T1', user_ref: user_ref)
      expect(Task.where_ref(user).count).to eq(1)
    end
  end

  describe 'ref singular (belongs_to)' do
    it 'defines getter that returns associated model' do
      t_ref = new_ref
      DB[:tasks].insert(ref: t_ref, name: 'T', user_ref: user_ref)
      task = Task[t_ref]
      expect(task.user).to be_a(User)
      expect(task.user.ref).to eq(user_ref)
    end

    it 'returns nil when ref is blank' do
      t_ref = new_ref
      DB[:tasks].insert(ref: t_ref, name: 'T', user_ref: nil)
      task = Task[t_ref]
      expect(task.user).to be_nil
    end
  end
end

# =========================================================================
#  composite_primary_keys.rb
# =========================================================================

describe 'plugins/db/composite_primary_keys.rb', :db_plugin do
  before(:each) { DB[:org_users].delete }

  describe '.primary_keys' do
    it 'returns defined composite keys' do
      expect(OrgUser.primary_keys).to eq([:org_ref, :user_ref])
    end
  end

  describe 'uniqueness enforcement on save' do
    it 'allows first record with given key combination' do
      expect {
        OrgUser.create(ref: new_ref, org_ref: 'org1', user_ref: 'u1')
      }.not_to raise_error
    end

    it 'raises when duplicate composite key is inserted' do
      OrgUser.create(ref: new_ref, org_ref: 'org1', user_ref: 'u1')
      expect {
        OrgUser.create(ref: new_ref, org_ref: 'org1', user_ref: 'u1')
      }.to raise_error(StandardError, /already exists/)
    end

    it 'allows same org_ref with different user_ref' do
      OrgUser.create(ref: new_ref, org_ref: 'org1', user_ref: 'u1')
      expect {
        OrgUser.create(ref: new_ref, org_ref: 'org1', user_ref: 'u2')
      }.not_to raise_error
    end
  end
end

# =========================================================================
#  array_search.rb
# =========================================================================

describe 'plugins/db/array_search.rb', :db_plugin do
  before(:each) { DB[:users].delete }

  describe '.all_tags' do
    before do
      DB[:users].insert(ref: new_ref, name: 'A', tags: Sequel.pg_array(['ruby', 'js']))
      DB[:users].insert(ref: new_ref, name: 'B', tags: Sequel.pg_array(['ruby', 'python']))
      DB[:users].insert(ref: new_ref, name: 'C', tags: Sequel.pg_array(['go']))
    end

    it 'returns tag names with counts' do
      result = User.dataset.all_tags
      expect(result).to be_an(Array)
      names = result.map { |r| r[:name] || r['name'] }
      expect(names).to include('ruby')
    end

    it 'respects limit' do
      result = User.dataset.all_tags(limit: 2)
      expect(result.length).to be <= 2
    end

    it 'works with custom field name' do
      result = User.dataset.all_tags(tags: :tags, limit: 10)
      expect(result).to be_an(Array)
    end
  end

  describe '.where_any' do
    before do
      DB[:users].insert(ref: new_ref, name: 'A', tags: Sequel.pg_array(['ruby', 'js']))
      DB[:users].insert(ref: new_ref, name: 'B', tags: Sequel.pg_array(['python']))
      DB[:users].insert(ref: new_ref, name: 'C', tags: Sequel.pg_array(['ruby', 'go']))
    end

    it 'finds records with any matching tag' do
      expect(User.dataset.where_any('ruby', :tags).count).to eq(2)
    end

    it 'accepts array of values' do
      expect(User.dataset.where_any(['ruby', 'python'], :tags).count).to eq(3)
    end

    it 'returns self when data is blank' do
      expect(User.dataset.where_any(nil, :tags).count).to eq(3)
      expect(User.dataset.where_any('', :tags).count).to eq(3)
    end
  end
end

# =========================================================================
#  model_tree.rb
# =========================================================================

describe 'plugins/db/model_tree.rb (ModelTree)', :db_plugin do
  before(:each) { DB[:tree_nodes].delete }

  let(:root_ref) { new_ref }
  let(:child_ref) { new_ref }
  let(:grandchild_ref) { new_ref }

  before do
    DB[:tree_nodes].insert(ref: root_ref, name: 'Root', parent_refs: Sequel.pg_array([], :text))
    DB[:tree_nodes].insert(ref: child_ref, name: 'Child', parent_refs: Sequel.pg_array([root_ref], :text))
    DB[:tree_nodes].insert(ref: grandchild_ref, name: 'Grandchild', parent_refs: Sequel.pg_array([child_ref, root_ref], :text))
  end

  describe '#parent' do
    it 'returns the direct parent (first element of parent_refs)' do
      child = TreeNode[child_ref]
      expect(child.parent.ref).to eq(root_ref)
    end
  end

  describe '#children' do
    it 'returns direct children' do
      root = TreeNode[root_ref]
      kids = root.children
      expect(kids.map(&:ref)).to include(child_ref)
    end
  end

  describe '#children_refs' do
    it 'returns self ref plus all descendant refs' do
      root = TreeNode[root_ref]
      refs = root.children_refs
      expect(refs).to include(root_ref, child_ref, grandchild_ref)
    end
  end

  describe '#parent_ref=' do
    it 'sets full ancestor chain in parent_refs' do
      new_node = TreeNode.new
      new_node[:ref] = new_ref
      new_node[:name] = 'New'
      new_node.parent_ref = child_ref
      expect(new_node[:parent_refs]).to include(child_ref, root_ref)
    end
  end
end

# =========================================================================
#  paginate.rb
# =========================================================================

describe 'plugins/db/paginate.rb', :db_plugin do
  before(:each) { DB[:users].delete }

  before do
    10.times do |i|
      DB[:users].insert(ref: new_ref, name: "P#{i.to_s.rjust(2, '0')}", created_at: Time.now.utc - (i * 60))
    end
  end

  # Paginate reads page from Lux.current.params[param], so we use a unique
  # param name and set it in the request URL to control pagination in tests.

  describe 'Paginate()' do
    it 'returns the requested page size' do
      result = Paginate(User.dataset.order(:name), size: 3, page: 1)
      expect(result.length).to eq(3)
    end

    it 'paginates correctly across pages' do
      Lux::Current.new('http://test?pg=1')
      page1 = Paginate(User.dataset.order(:name), size: 4, param: :pg)
      Lux::Current.new('http://test?pg=2')
      page2 = Paginate(User.dataset.order(:name), size: 4, param: :pg)
      expect(page1.map(&:name) & page2.map(&:name)).to be_empty
    end

    it 'sets paginate_page from request params' do
      Lux::Current.new('http://test?pg=3')
      result = Paginate(User.dataset, size: 5, param: :pg)
      expect(result.paginate_page).to eq(3)
    end

    it 'sets paginate_next to true when more records exist' do
      result = Paginate(User.dataset.order(:name), size: 5, page: 1)
      expect(result.paginate_next).to be true
    end

    it 'sets paginate_next to false on last page' do
      result = Paginate(User.dataset.order(:name), size: 20, page: 1)
      expect(result.paginate_next).to be false
    end

    it 'sets paginate_opts' do
      Lux::Current.new('http://test?pg=2')
      result = Paginate(User.dataset, size: 5, param: :pg)
      opts = result.paginate_opts
      expect(opts[:page]).to eq(2)
      expect(opts[:param]).to eq(:pg)
    end

    it 'defaults page to 1 for invalid values' do
      result = Paginate(User.dataset, size: 5, page: 0)
      expect(result.paginate_page).to eq(1)
    end
  end

  describe 'dataset #page / #paginate' do
    it 'works as dataset method' do
      result = User.dataset.order(:name).page(size: 3, page: 1)
      expect(result.length).to eq(3)
      expect(result).to respond_to(:paginate_next)
    end

    it 'is aliased as #paginate' do
      result = User.dataset.order(:name).paginate(size: 3, page: 1)
      expect(result.length).to eq(3)
    end
  end
end

# =========================================================================
#  link_objects.rb – plural ref (has_many)
# =========================================================================

describe 'plugins/db/link_objects.rb – plural ref', :db_plugin do
  before(:each) do
    DB[:users].delete
    DB[:tasks].delete
    DB[:comments].delete
    DB[:projects].delete
  end

  describe 'link :users (array-based has_many via user_refs[])' do
    let(:u1_ref) { new_ref }
    let(:u2_ref) { new_ref }

    before do
      DB[:users].insert(ref: u1_ref, name: 'Alice')
      DB[:users].insert(ref: u2_ref, name: 'Bob')
    end

    it 'returns associated models from the refs array' do
      p_ref = new_ref
      DB[:projects].insert(ref: p_ref, name: 'P1', user_refs: Sequel.pg_array([u1_ref, u2_ref]))
      project = Project[p_ref]

      users = project.users
      expect(users.length).to eq(2)
      expect(users.map(&:name)).to contain_exactly('Alice', 'Bob')
    end

    it 'returns empty array when refs array is empty' do
      p_ref = new_ref
      DB[:projects].insert(ref: p_ref, name: 'P2', user_refs: Sequel.pg_array([], :text))
      project = Project[p_ref]

      expect(project.users).to eq([])
    end

    it 'returns empty array when refs is nil' do
      p_ref = new_ref
      DB[:projects].insert(ref: p_ref, name: 'P3')
      project = Project[p_ref]

      expect(project.users).to eq([])
    end
  end

  describe 'link :comments (reverse-lookup has_many)' do
    let(:task_ref) { new_ref }

    before do
      DB[:tasks].insert(ref: task_ref, name: 'MyTask')
    end

    it 'returns a dataset of associated records via reverse FK' do
      DB[:comments].insert(ref: new_ref, body: 'C1', task_ref: task_ref)
      DB[:comments].insert(ref: new_ref, body: 'C2', task_ref: task_ref)
      DB[:comments].insert(ref: new_ref, body: 'Other', task_ref: 'other')

      task = Task[task_ref]
      comments = task.comments

      expect(comments).to respond_to(:count)
      expect(comments.count).to eq(2)
      expect(comments.map(&:body)).to contain_exactly('C1', 'C2')
    end

    it 'returns empty dataset when no associated records exist' do
      task = Task[task_ref]
      expect(task.comments.count).to eq(0)
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

      expect(task[:user_ref]).to eq(u_ref)
    end
  end

  describe 'where_ref via parent_type/parent_ref fallback' do
    let(:user_ref) { new_ref }
    let!(:user) do
      DB[:users].insert(ref: user_ref, name: 'Parent')
      User[user_ref]
    end

    it 'scopes by parent_type and parent_ref when no FK column exists' do
      DB[:notes].insert(ref: new_ref, body: 'N1', parent_type: 'User', parent_ref: user_ref)
      DB[:notes].insert(ref: new_ref, body: 'N2', parent_type: 'User', parent_ref: 'other')

      expect(Note.where_ref(user).count).to eq(1)
      expect(Note.where_ref(user).first.body).to eq('N1')
    end
  end
end

# =========================================================================
#  _parent_model.rb – parent_type + parent_ref style
# =========================================================================

describe 'plugins/db/_parent_model.rb – parent_type/parent_ref style', :db_plugin do
  before(:each) do
    DB[:users].delete
    DB[:notes].delete
  end

  let(:user_ref) { new_ref }
  let!(:user) do
    DB[:users].insert(ref: user_ref, name: 'Owner')
    User[user_ref]
  end

  describe '#parent= (parent_type/parent_ref)' do
    it 'sets parent_type and parent_ref from a model' do
      note = Note.new
      note[:ref] = new_ref
      note[:body] = 'Hello'
      note.parent = user

      expect(note[:parent_type]).to eq('User')
      expect(note[:parent_ref]).to eq(user_ref)
    end
  end

  describe '#parent getter (parent_type/parent_ref)' do
    it 'retrieves parent from parent_type and parent_ref' do
      n_ref = new_ref
      DB[:notes].insert(ref: n_ref, body: 'Test', parent_type: 'User', parent_ref: user_ref)
      note = Note[n_ref]

      expect(note.parent).to be_a(User)
      expect(note.parent.ref).to eq(user_ref)
    end

    it 'caches the parent after first access' do
      n_ref = new_ref
      DB[:notes].insert(ref: n_ref, body: 'Test', parent_type: 'User', parent_ref: user_ref)
      note = Note[n_ref]

      parent1 = note.parent
      parent2 = note.parent
      expect(parent1.object_id).to eq(parent2.object_id)
    end
  end

  describe '#parent with argument (chaining setter)' do
    it 'sets parent and returns self for chaining' do
      note = Note.new
      note[:ref] = new_ref
      result = note.parent(user)

      expect(result).to be(note)
      expect(note[:parent_type]).to eq('User')
      expect(note[:parent_ref]).to eq(user_ref)
    end
  end

  describe '#parent?' do
    it 'returns truthy for model with parent_type column' do
      note = Note.new
      expect(note.parent?).to be_truthy
    end
  end

  describe '.for_parent (parent_type/parent_ref)' do
    it 'scopes records to given parent' do
      DB[:notes].insert(ref: new_ref, body: 'N1', parent_type: 'User', parent_ref: user_ref)
      DB[:notes].insert(ref: new_ref, body: 'N2', parent_type: 'User', parent_ref: 'other')
      DB[:notes].insert(ref: new_ref, body: 'N3', parent_type: 'Task', parent_ref: user_ref)

      notes = Note.for_parent(user)
      expect(notes.count).to eq(1)
      expect(notes.first.body).to eq('N1')
    end
  end

  describe 'DatasetMethods#where_parent (parent_type/parent_ref)' do
    it 'filters dataset by parent_type and parent_ref' do
      DB[:notes].insert(ref: new_ref, body: 'N1', parent_type: 'User', parent_ref: user_ref)
      DB[:notes].insert(ref: new_ref, body: 'N2', parent_type: 'Task', parent_ref: user_ref)

      result = Note.dataset.where_parent(user)
      expect(result.count).to eq(1)
      expect(result.first.body).to eq('N1')
    end
  end
end

# =========================================================================
#  create_limit.rb
# =========================================================================

describe 'plugins/db/create_limit.rb', :db_plugin do
  before(:each) do
    DB[:notes].delete
    DB[:users].delete
  end

  let(:current_user) do
    ref = new_ref
    DB[:users].insert(ref: ref, name: 'Creator')
    User[ref]
  end

  describe 'ClassMethods' do
    it '.create_limit stores the limit configuration' do
      expect(Note.cattr.create_limit_data).to eq([3, 1.hour, nil])
    end
  end

  describe 'validate' do
    it 'raises when no user is logged in' do
      User.current = nil
      note = Note.new(ref: new_ref, body: 'Test')
      expect { note.save }.to raise_error(Lux::Error, /log in/)
    end

    it 'allows creation when under the limit' do
      User.current = current_user
      note = Note.new(ref: new_ref, body: 'Test', creator_ref: current_user.ref)
      expect { note.save }.not_to raise_error
    end

    it 'skips check on existing records (update)' do
      User.current = current_user
      note = Note.create(ref: new_ref, body: 'Test', creator_ref: current_user.ref)
      expect { note.update(body: 'Updated') }.not_to raise_error
    end

    it 'skips check when model has no creator_ref column' do
      User.current = current_user
      # Comment has no creator_ref, so create_limit validation is skipped
      comment = Comment.new(ref: new_ref, body: 'Hi')
      expect { comment.save }.not_to raise_error
    end

    context 'when over the limit' do
      before do
        User.current = current_user
        # Bypass the Lux.env.test? guard
        allow(Lux.env).to receive(:test?).and_return(false)
      end

      it 'adds a validation error when rate limit is exceeded' do
        3.times { |i| Note.create(ref: new_ref, body: "N#{i}", creator_ref: current_user.ref) }

        note = Note.new(ref: new_ref, body: 'One too many', creator_ref: current_user.ref)
        note.valid?

        expect(note.errors[:base]).to be_an(Array)
        expect(note.errors[:base].first).to include('max of 3')
        expect(note.errors[:base].first).to include('Spam protection')
      end

      it 'does not block different users' do
        3.times { |i| Note.create(ref: new_ref, body: "N#{i}", creator_ref: current_user.ref) }

        other_ref = new_ref
        DB[:users].insert(ref: other_ref, name: 'Other')
        other_user = User[other_ref]
        User.current = other_user

        note = Note.new(ref: new_ref, body: 'From other', creator_ref: other_user.ref)
        expect(note.valid?).to be true
      end
    end
  end

  # ---------------------------------------------------------------------------
  # AutoMigrate – type conversions
  # ---------------------------------------------------------------------------

  describe 'AutoMigrate type conversions' do
    let(:table_name) { :am_type_test }

    before(:all) do
      load File.expand_path('../../plugins/db/auto_migrate/auto_migrate.rb', __dir__)
      AutoMigrate.auto_confirm = true
    end

    before(:each) do
      DB.drop_table?(table_name)
    end

    after(:all) do
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

      expect(col_type(:count)).to eq('integer')
      expect(DB[table_name].first[:count]).to eq(42)
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

      expect(col_type(:active)).to eq('boolean')
      rows = DB[table_name].order(:ref).all
      expect(rows[0][:active]).to eq(true)
      expect(rows[1][:active]).to eq(false)
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

      expect(col_type(:code)).to eq('character varying(50)')
      expect(DB[table_name].first[:code]).to eq('123')
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

      expect(col_type(:flag)).to eq('boolean')
      rows = DB[table_name].order(:ref).all
      expect(rows[0][:flag]).to eq(true)
      expect(rows[1][:flag]).to eq(false)
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

      expect(col_type(:flag)).to eq('integer')
      rows = DB[table_name].order(:ref).all
      expect(rows[0][:flag]).to eq(1)
      expect(rows[1][:flag]).to eq(0)
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

      expect(col_type(:price)).to eq('integer')
      expect(DB[table_name].first[:price]).to eq(3)
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

      expect(col_type(:amount)).to include('numeric')
      expect(DB[table_name].first[:amount].to_f).to eq(100.0)
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

      expect(col_type(:born_on)).to eq('date')
      expect(DB[table_name].first[:born_on]).to eq(Date.new(2025, 6, 15))
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

      expect(col_type(:happened_at)).to include('timestamp')
      expect(DB[table_name].first[:happened_at]).to be_a(Time)
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

      expect(col_type(:started)).to include('timestamp')
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

      expect(col_type(:started)).to eq('date')
      expect(DB[table_name].first[:started]).to eq(Date.new(2025, 6, 15))
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

      expect(col_type(:price)).to include('numeric')
      expect(DB[table_name].first[:price].to_f).to eq(19.99)
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

      expect(col_type(:ids)).to eq('integer[]')
      expect(DB[table_name].first[:ids]).to eq([1, 2, 3])
    end

    it 'prints warning for unknown conversion' do
      DB.create_table(table_name) do
        String :ref, primary_key: true
        TrueClass :flag, default: false
      end

      expect {
        run_migrate do |f|
          f.date :flag
        end
      }.to output(/Cannot auto-convert/).to_stdout
    end
  end
end
