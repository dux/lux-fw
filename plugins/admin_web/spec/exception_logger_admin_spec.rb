require 'test_helper'

# Boot-level config that Lux.boot! would normally set; required because this
# spec drives the full Lux.render request pipeline.
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

# Load just enough of the db plugin to get the schema DSL + hooks.
require_relative '../../db/loader.rb'
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

# Stub User so LuxException.add's `User.current.email rescue nil` resolves.
unless defined?(User)
  class User
    def self.current = nil
  end
end

# Fresh tables for each run.
DB.drop_table?(:lux_exception_logs, :lux_exceptions)

DB.create_table :lux_exceptions do
  String  :ref, primary_key: true
  String  :uid, index: true
  String  :klass, index: true
  String  :message, text: true
  String  :body, text: true
  Integer :times, default: 1
  TrueClass :is_resolved
  Time    :first_at
  Time    :last_at, index: true
end

DB.create_table :lux_exception_logs do
  String :ref, primary_key: true
  String :uid, index: true
  String :url, text: true
  String :email, index: true
  String :ip
  String :env, text: true
  Time   :created_at, index: true
end

# Boot the plugin: registers the LuxException + LuxExceptionLog models.
# The GET pages (list + show) are rendered directly via Lux::Template.render
# in this spec; show.haml handles the inline toggle itself when the request
# carries a `?toggle=<uid>` param.
require_relative '../loader.rb'

# Initialise the application so the per-action route registry is reachable
# via Lux.render. The GET pages would be rendered by the host's
# AdminController via auto_find_template; this spec renders them directly
# via Lux::Template.render to keep the test free of host-app stubs.
Lux.app do; end

VIEWS_ROOT ||= File.expand_path('../mount/app/views', __dir__)

###

describe 'exception_logger admin flow' do
  before do
    LuxException.dataset.delete
    LuxExceptionLog.dataset.delete
  end

  def render_view path, params: {}
    Lux::Current.new('http://test%s' % path, query_string: params)
    # show.haml's inline toggle path calls redirect_to, which `throw :done`.
    # The host controller wraps render with catch(:done); mirror that here.
    catch :done do
      Lux::Template.render(self, '%s%s' % [VIEWS_ROOT, path])
    end
  end

  it 'flows through add, list, show, resolve' do
    # 1. table is clear
    _(LuxException.count).must_equal 0

    # 2. add an exception
    err = RuntimeError.new('something blew up')
    err.set_backtrace(['/app/code/foo.rb:42:in `bar\''])
    exep = LuxException.add(err)

    _(LuxException.count).must_equal 1
    _(LuxExceptionLog.count).must_equal 1
    _(exep.klass).must_equal 'RuntimeError'
    refute exep.is_resolved

    # 3. list page renders the new row (auto_find_template path in the host)
    body = render_view '/admin/plugins/exception_logger/root'
    _(body).must_include 'something blew up'
    _(body).must_include 'RuntimeError'
    _(body).must_include 'total: 1'

    # 4. show page renders details + the Open/Resolved toggle
    body = render_view '/admin/plugins/exception_logger/show', params: { uid: exep.uid }
    _(body).must_include 'Backtrace'
    _(body).must_include 'Open'
    _(body).must_include 'Resolved'
    _(body).must_include 'something blew up'

    # 5. Hitting the show page with `?toggle=<uid>` flips is_resolved inline
    #    and redirects to the clean URL (redirect_to throws :done, which
    #    render_view catches).
    render_view '/admin/plugins/exception_logger/show', params: { uid: exep.uid, toggle: exep.uid }
    _(Lux.current.response.status).must_equal 302
    _(Lux.current.response.headers['location']).must_match %r{\A/admin/plugins/exception_logger/show\?.*uid=#{exep.uid}}
    _(exep.refresh.is_resolved).must_equal true

    # 6. Same trigger flips it back.
    render_view '/admin/plugins/exception_logger/show', params: { uid: exep.uid, toggle: exep.uid }
    _(exep.refresh.is_resolved).must_equal false
  end
end
