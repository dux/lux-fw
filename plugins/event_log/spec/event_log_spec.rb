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

# Fresh table each run, built through the real db:am path so the spec covers
# the array column, GIN index and UNLOGGED switch - not a hand-written copy.
DB.drop_table?(:lux_event_logs)

require_relative '../loader.rb'
AutoMigrate.apply_schema LuxEventLog

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
    _(cols[:data][:db_type]).must_equal 'character varying(200)'
    _(cols[:json_data][:db_type]).must_equal 'jsonb'
    _(cols[:created_at][:db_type]).must_match(/\Atimestamp/)

    persistence = DB.fetch("SELECT relpersistence FROM pg_class WHERE relname = 'lux_event_logs'").first[:relpersistence]
    _(persistence).must_equal 'u'

    indexes = DB.fetch("SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'lux_event_logs'").all
    _(indexes.map { _1[:indexdef] }.join(' ')).must_match(/USING gin/i)
    _(indexes.map { _1[:indexname] }.join(' ')).must_include 'created_at'
  end

  it 'logs events and queries them by tag' do
    LuxEventLog.log ['page_view', 'mobile'], '/pricing', { referrer: 'google.com' }
    LuxEventLog.log ['page_view'], '/home'
    LuxEventLog.log :user_login

    _(LuxEventLog.count).must_equal 3

    row = LuxEventLog.where_all('mobile').first
    _(row.tags.to_a).must_equal ['page_view', 'mobile']
    _(row.data).must_equal '/pricing'
    _(row.json_data['referrer']).must_equal 'google.com'
    _(row.ref.length).must_equal 16
    _(row.created_at).wont_be_nil

    _(LuxEventLog.where_all(['page_view', 'mobile']).count).must_equal 1
    _(LuxEventLog.where_any(['mobile', 'user_login']).count).must_equal 2

    top = LuxEventLog.all_tags
    _(top.first[:name]).must_equal 'page_view'
    _(top.first[:cnt]).must_equal 2
  end

  it 'fast-inserts via .add, skipping the model layer' do
    ref = LuxEventLog.add tags: [:api, :v2], data: 'GET /users', json_data: { ms: 152 }

    _(ref.length).must_equal 16

    row = LuxEventLog[ref]
    _(row.tags.to_a).must_equal ['api', 'v2']
    _(row.data).must_equal 'GET /users'
    _(row.json_data['ms']).must_equal 152
    _(row.created_at).wont_be_nil

    # oversize data is truncated to the varchar(200) limit, not raised on
    ref = LuxEventLog.add tags: ['long'], data: 'x' * 500
    _(LuxEventLog[ref].data.length).must_equal 200
  end

  it 'renders the admin list and narrows it with the tag filter' do
    LuxEventLog.log ['page_view', 'mobile'], '/pricing', { referrer: 'google.com' }
    LuxEventLog.log ['user_login'], 'login-marker'

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
