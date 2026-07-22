require 'test_helper'

# Boot-level config that Lux.boot! would normally set; required because this
# spec renders the admin haml via the full Lux template pipeline.
%i(serve_static_files use_autoroutes asset_root deploy_timestamp csrf).each do |k|
  Lux.config[k] = false unless Lux.config.key?(k)
end
Lux.config[:plugins] ||= []
Lux.config[:logger_path_mask]     ||= './log/%s.log'
Lux.config[:logger_files_to_keep] ||= 3
Lux.config[:logger_file_max_size] ||= 10_240_000
Lux.config[:logger_formatter]     ||= nil

# --- DB bootstrap ---------------------------------------------------------
Object.send(:remove_const, :DB) if defined?(DB)
DB ||= Sequel.connect('postgres:///lux_fw_test')
DB.loggers.clear
DB.extension :pg_array, :pg_json

# Load just enough of the db plugin to get the schema DSL + AutoMigrate.
require_relative '../../db/loader.rb'
Sequel::Model.require_valid_table = false
Sequel::Model.plugin :lux_schema
Sequel::Model.plugin :lux_hooks
Sequel::Model.plugin :lux_before_save

# Host-level ApplicationModel stand-in: ref primary key with auto-fill.
unless defined?(ApplicationModel)
  ApplicationModel = Class.new(Sequel::Model) do
    set_primary_key :ref
    unrestrict_primary_key
    plugin :lux_schema

    def before_create
      self[:ref] ||= Lux::Utils::Ref.generate
      super
    end
  end
end

# Fresh tables each run, built through the real db:am path so the spec covers
# the array column, GIN index and UNLOGGED switch - not a hand-written copy.
DB.drop_table?(:lux_event_logs)
DB.drop_table?(:lux_event_log_views)

require_relative '../loader.rb'
AutoMigrate.apply_schema LuxEventLog
AutoMigrate.apply_schema LuxEventLogView

# web_common provides the view helpers root.haml uses (table + paginate).
# Load through the plugin system - it sweeps load/**/*.rb; a bare require
# of loader.rb loads none of the helpers.
Lux::Plugin.load File.expand_path('../../web_common', __dir__)

# Initialise the application so Lux.render works; the GET page is rendered
# by the host's AdminController via auto_find_template, here we render the
# template directly to keep the test free of host-app stubs.
Lux.app do; end

EVENT_LOG_VIEWS ||= File.expand_path('../mount/app/views', __dir__)

###

describe 'event_log plugin' do
  before do
    LuxEventLog.dataset.delete
    LuxEventLogView.dataset.delete
  end

  def render_view path, params: {}
    Lux::Current.new('http://test%s' % path, query_string: params)
    # :html mixes in HtmlHelper (paginate); ApplicationHelper (table) comes free
    scope = Lux::Template::Helper.new self, :html
    catch :done do
      Lux::Template.render(scope, '%s%s' % [EVENT_LOG_VIEWS, path])
    end
  end

  it 'creates the lux_event_logs table with the expected shape' do
    cols = DB.schema(:lux_event_logs).to_h

    _(cols[:tags][:db_type]).must_match(/\[\]\z/)
    _(cols[:data][:db_type]).must_equal 'jsonb'
    _(cols[:created_at][:db_type]).must_match(/\Atimestamp/)
    _(cols.key?(:json_data)).must_equal false

    persistence = DB.fetch("SELECT relpersistence FROM pg_class WHERE relname = 'lux_event_logs'").first[:relpersistence]
    _(persistence).must_equal 'u'

    indexes = DB.fetch("SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'lux_event_logs'").all
    _(indexes.map { _1[:indexdef] }.join(' ')).must_match(/USING gin/i)
    _(indexes.map { _1[:indexname] }.join(' ')).must_include 'created_at'
  end

  it 'logs events and queries them by tag' do
    LuxEventLog.log ['page_view', 'mobile'], path: '/pricing', referrer: 'google.com'
    LuxEventLog.log ['page_view'], path: '/home'
    LuxEventLog.log :user_login

    _(LuxEventLog.count).must_equal 3

    row = LuxEventLog.where_all('mobile').first
    _(row.tags.to_a).must_equal ['page_view', 'mobile']
    _(row.data['path']).must_equal '/pricing'
    _(row.data['referrer']).must_equal 'google.com'
    _(row.ref.length).must_equal 16
    _(row.created_at).wont_be_nil

    _(LuxEventLog.where_all(['page_view', 'mobile']).count).must_equal 1
    _(LuxEventLog.where_any(['mobile', 'user_login']).count).must_equal 2

    top = LuxEventLog.all_tags
    _(top.first[:name]).must_equal 'page_view'
    _(top.first[:cnt]).must_equal 2
  end

  it 'fast-inserts via .add, skipping the model layer' do
    ref = LuxEventLog.add tags: [:api, :v2], data: { path: 'GET /users', ms: 152 }

    _(ref.length).must_equal 16

    row = LuxEventLog[ref]
    _(row.tags.to_a).must_equal ['api', 'v2']
    _(row.data['path']).must_equal 'GET /users'
    _(row.data['ms']).must_equal 152
    _(row.created_at).wont_be_nil

    # nil data falls back to an empty json object
    ref = LuxEventLog.add tags: ['bare'], data: nil
    _(LuxEventLog[ref].data.to_h).must_equal({})
  end

  it 'computes funnels over an ordered tag list' do
    LuxEventLog.add tags: [:visit],    data: { user: 'u1' }
    LuxEventLog.add tags: [:visit],    data: { user: 'u2' }
    LuxEventLog.add tags: [:visit],    data: { user: 'u2' }   # same actor twice
    LuxEventLog.add tags: [:signup],   data: { user: 'u1' }
    LuxEventLog.add tags: [:signup],   data: { user: 'u2' }
    LuxEventLog.add tags: [:purchase], data: { user: 'u1' }

    steps = LuxEventLog.funnel [:visit, :signup, :purchase]
    _(steps.map { _1[:tag] }).must_equal ['visit', 'signup', 'purchase']
    _(steps.map { _1[:count] }).must_equal [3, 2, 1]
    _(steps[0][:pct]).must_equal 100.0
    _(steps[0][:step_pct]).must_be_nil
    _(steps[1][:step_pct]).must_equal 66.7
    _(steps[2][:pct]).must_equal 33.3

    # unique by a key inside the data payload
    steps = LuxEventLog.funnel [:visit, :signup, :purchase], unique: 'user'
    _(steps.map { _1[:count] }).must_equal [2, 2, 1]

    # unique: true = distinct whole data values
    steps = LuxEventLog.funnel [:visit], unique: true
    _(steps.map { _1[:count] }).must_equal [2]

    # time window: backdated events fall out
    LuxEventLog.dataset.xwhere("data->>'user' = ?", 'u2').update(created_at: Time.now - 10 * 86_400)
    steps = LuxEventLog.funnel [:visit, :signup], since: Time.now - 5 * 86_400
    _(steps.map { _1[:count] }).must_equal [1, 1]
  end

  it 'renders the funnel page' do
    LuxEventLog.add tags: [:visit],  data: { user: 'u1' }
    LuxEventLog.add tags: [:signup], data: { user: 'u1' }

    body = render_view '/admin/plugins/event_log/funnel', params: { tags: 'visit, signup' }
    _(body).must_include 'visit'
    _(body).must_include 'signup'
    _(body).must_include '100.0%'
    _(body).must_include 'bg-blue-600'   # funnel bars

    body = render_view '/admin/plugins/event_log/funnel', params: { tags: 'visit, signup', unique: 'user' }
    _(body).must_include 'unique by user'

    body = render_view '/admin/plugins/event_log/funnel'
    _(body).must_include 'at least two comma separated tags'
  end

  it 'upserts saved views by name' do
    LuxEventLogView.store 'daily', '/admin/plugins/event_log?days=1'
    LuxEventLogView.store 'daily', '/admin/plugins/event_log?days=1&tag=api'

    _(LuxEventLogView.count).must_equal 1
    _(LuxEventLogView.first.path).must_equal '/admin/plugins/event_log?days=1&tag=api'
  end

  it 'saves and forgets views from the admin pages via url params' do
    # ?save_as stores the clean url (sans save_as) and redirects to it
    render_view '/admin/plugins/event_log/root', params: { days: '30', save_as: 'monthly' }
    _(Lux.current.response.status).must_equal 302
    _(Lux.current.response.headers['location']).must_equal '/admin/plugins/event_log/root?days=30'

    view = LuxEventLogView.first(name: 'monthly')
    _(view.path).must_equal '/admin/plugins/event_log/root?days=30'

    # saved views render as badges; the active one is highlighted
    body = render_view '/admin/plugins/event_log/root', params: { days: '30' }
    _(body).must_include 'monthly'
    _(body).must_include 'badge-success'

    # funnel page lists them too
    body = render_view '/admin/plugins/event_log/funnel'
    _(body).must_include 'monthly'

    # ?forget deletes and redirects back
    render_view '/admin/plugins/event_log/root', params: { forget: 'monthly' }
    _(Lux.current.response.status).must_equal 302
    _(LuxEventLogView.count).must_equal 0
  end

  it 'filters the list by an explicit from/to window' do
    LuxEventLog.log ['fresh'], m: 'fresh-marker'
    LuxEventLog.log ['stale'], m: 'stale-marker'
    LuxEventLog.dataset.xwhere("data->>'m' = ?", 'stale-marker').update(created_at: Time.now - 30 * 86_400)

    # from/to overrides the days preset (default 7d would hide stale anyway)
    body = render_view '/admin/plugins/event_log/root', params: { from: (Date.today - 60).to_s }
    _(body).must_include 'fresh-marker'
    _(body).must_include 'stale-marker'

    body = render_view '/admin/plugins/event_log/root', params: { from: (Date.today - 7).to_s }
    _(body).must_include 'fresh-marker'
    _(body).wont_include 'stale-marker'

    body = render_view '/admin/plugins/event_log/root', params: { from: (Date.today - 60).to_s, to: (Date.today - 14).to_s }
    _(body).wont_include 'fresh-marker'
    _(body).must_include 'stale-marker'
  end

  it 'renders the admin list and narrows it with the tag filter' do
    LuxEventLog.log ['page_view', 'mobile'], path: '/pricing', referrer: 'google.com'
    LuxEventLog.log ['user_login'], m: 'login-marker'

    body = render_view '/admin/plugins/event_log/root'
    _(body).must_include 'total: 2'
    _(body).must_include '/pricing'
    _(body).must_include 'login-marker'
    _(body).must_include 'referrer'

    body = render_view '/admin/plugins/event_log/root', params: { tag: 'mobile' }
    _(body).must_include 'total: 1'
    _(body).must_include '/pricing'
    _(body).wont_include 'login-marker'
  end
end
