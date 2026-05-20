require_relative '../loader'

# Mirrors the real-world ModelApi + generate pattern used in lux apps
# (e.g. ~/dev/dux/accounting/app/api/model_api.rb). Verifies that:
#   * a self.generate macro can dynamically define collection (for :create)
#     and ref-scoped (for :show / :update / :destroy) actions
#   * root before/after callbacks load @object for both collection and ref
#   * private helpers at root remain accessible to action bodies but are
#     never exposed as API endpoints
#   * child classes can override generated parent actions and call super /
#     super! to chain into the parent implementation

# In-memory data store

class Widget
  attr_accessor :id, :name, :is_deleted
  STORE = []
  ID_SEQ = [0]

  def initialize(name)
    @id = (ID_SEQ[0] += 1)
    @name = name
    @is_deleted = false
    STORE.push self
  end

  def self.find(id)
    STORE.find { |w| w.id == id.to_i }
  end

  def export
    { id: id, name: name, is_deleted: is_deleted }
  end
end

Widget.new('alpha')
Widget.new('beta')

# Base "model" API with a generate macro

class ExampleModelApi < ApplicationApi
  def self.generate name
    if name == :create
      class_eval { define_method(name) { send("generated_#{name}") } }
    else
      ref { define_method(name) { send("generated_#{name}") } }
    end
  end

  before do
    @object = if @ref
      Widget.find(@ref) or error 'Object not found'
    else
      Widget.new(params[:name] || 'unnamed')
    end
  end

  after do
    response.meta :model_class, 'Widget'
  end

  private

  def generated_show
    @object.export
  end

  def generated_create
    message "Created #{@object.name}"
    @object.export
  end

  def generated_update
    @object.name = params[:name] if params[:name]
    @object.export.merge(updated: true)
  end

  def generated_destroy
    @object.is_deleted = true
    message 'Destroyed'
    true
  end

  def display_name
    @object.class.to_s
  end
end

# Child class - generated CRUD + custom overrides + super!

class WidgetsApi < ExampleModelApi
  # Use generate for :show and :destroy as-is
  generate :show
  generate :destroy

  # For :update we want to wrap, so define it directly via the parent's
  # generated_* private helper rather than calling `generate :update`.
  ref do
    define_method(:update) do
      base = send(:generated_update)
      base.merge(child_touched: display_name)
    end

    # New ref action that uses a parent private helper
    def archive
      { display: display_name, ref: @ref }
    end
  end

  # Collection :create using generate, then add a sibling wrapper action.
  generate :create

  def create_wrapped
    base = send(:generated_create)
    base.merge(child_create_wrapped: true)
  end
end

describe 'inherited model pattern' do
  context 'generate macro dispatch' do
    it 'create lives at the root (collection)' do
      expect(WidgetsApi.opts[:collection]).to have_key(:create)
    end

    it 'show, update, destroy live inside ref scope (member)' do
      %i[show update destroy].each do |name|
        expect(WidgetsApi.opts[:member]).to have_key(name)
      end
    end

    it 'show_ref / update_ref / destroy_ref exist as instance methods' do
      expect(WidgetsApi.instance_methods).to include(:show_ref, :update_ref, :destroy_ref, :archive_ref)
    end

    it 'collection create_wrapped wraps generated_create via helper call' do
      response = WidgetsApi.render :create_wrapped, params: { name: 'wrapped' }
      expect(response[:success]).to eq(true)
      expect(response[:data][:name]).to eq('wrapped')
      expect(response[:data][:child_create_wrapped]).to eq(true)
    end
  end

  context 'parent generated action invoked from child' do
    it 'show returns parent body (loaded via before)' do
      widget = Widget.new('for-show')
      response = WidgetsApi.render :show, id: widget.id
      expect(response[:success]).to eq(true)
      expect(response[:data][:name]).to eq('for-show')
    end

    it 'update overrides parent via super! and adds child_touched' do
      widget = Widget.new('original')
      response = WidgetsApi.render :update, id: widget.id, params: { name: 'modified' }
      expect(response[:success]).to eq(true)
      expect(response[:data][:name]).to eq('modified')
      expect(response[:data][:updated]).to eq(true)
      expect(response[:data][:child_touched]).to eq('Widget')
    end

    it 'plain create (via generate) returns parent body' do
      response = WidgetsApi.render :create, params: { name: 'fresh' }
      expect(response[:success]).to eq(true)
      expect(response[:data][:name]).to eq('fresh')
    end
  end

  context 'private helpers not exposed as endpoints' do
    it 'generated_show is not callable as an API method' do
      widget = Widget.new('hidden')
      response = WidgetsApi.render :generated_show, id: widget.id
      expect(response[:success]).to eq(false)
      expect(response[:error][:messages].first).to include('Api method')
    end

    it 'display_name is not callable as an API method' do
      widget = Widget.new('also-hidden')
      response = WidgetsApi.render :display_name, id: widget.id
      expect(response[:success]).to eq(false)
    end

    it 'archive (ref action) can still call private parent helper display_name' do
      widget = Widget.new('arc')
      response = WidgetsApi.render :archive, id: widget.id
      expect(response[:success]).to eq(true)
      expect(response[:data][:display]).to eq('Widget')
      expect(response[:data][:ref].to_i).to eq(widget.id)
    end
  end

  context 'root before runs for both collection and ref child actions' do
    it 'before loaded @object visible to ref action show' do
      widget = Widget.new('before-check')
      response = WidgetsApi.render :show, id: widget.id
      expect(response[:data][:name]).to eq('before-check')
    end

    it 'before built fresh @object for collection action create' do
      response = WidgetsApi.render :create, params: { name: 'created-via-before' }
      expect(response[:data][:name]).to eq('created-via-before')
    end

    it 'after sets :model_class meta on both' do
      widget = Widget.new('meta-check')
      coll = WidgetsApi.render :create, params: { name: 'x' }
      memb = WidgetsApi.render :show, id: widget.id
      expect(coll[:meta][:model_class]).to eq('Widget')
      expect(memb[:meta][:model_class]).to eq('Widget')
    end
  end
end
