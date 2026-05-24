require 'test_helper'

describe Lux::Response::Cors do
  # Minimal stand-ins so we can drive Cors.apply without booting the app.
  Headers ||= Class.new(Hash) do
    def []=(k, v); super(k.to_s.downcase, v); end
    def [](k);     super(k.to_s.downcase); end
  end

  Request ||= Struct.new(:env, :request_method)
  ResponseStub ||= Struct.new(:headers, :current, :_status, :_body) do
    def status(n); self._status = n; end
    def body(b);   self._body = b;   end
  end
  CurrentStub ||= Struct.new(:request)

  def build_response request_method: 'GET', origin: nil, acrm: nil
    env = {}
    env['HTTP_ORIGIN'] = origin if origin
    env['HTTP_ACCESS_CONTROL_REQUEST_METHOD'] = acrm if acrm
    req = Request.new(env, request_method)
    ResponseStub.new(Headers.new, CurrentStub.new(req))
  end

  describe ':all shortcut' do
    it 'sets permissive headers' do
      r = build_response(origin: 'https://x.example')
      Lux::Response::Cors.apply r, :all

      _(r.headers['access-control-allow-origin']).must_equal '*'
      _(r.headers['access-control-allow-methods']).must_include 'GET'
      _(r.headers['access-control-allow-methods']).must_include 'OPTIONS'
      _(r.headers['access-control-allow-headers']).must_include 'Authorization'
      _(r.headers['access-control-max-age']).must_equal '600'
      _(r.headers['access-control-allow-credentials']).must_be_nil
    end

    it 'rejects :all + credentials:true' do
      r = build_response
      _{ Lux::Response::Cors.apply r, :all, credentials: true }.must_raise ArgumentError
    end
  end

  describe 'explicit origins list' do
    it 'echoes the request Origin when it matches the list' do
      r = build_response(origin: 'https://app.example.com')
      Lux::Response::Cors.apply r, origins: %w[https://app.example.com https://staging.example.com]
      _(r.headers['access-control-allow-origin']).must_equal 'https://app.example.com'
      _(r.headers['vary']).must_include 'Origin'
    end

    it 'omits the header when Origin is not on the list' do
      r = build_response(origin: 'https://evil.example')
      Lux::Response::Cors.apply r, origins: %w[https://app.example.com]
      _(r.headers['access-control-allow-origin']).must_be_nil
    end

    it 'omits the header when there is no Origin in the request' do
      r = build_response
      Lux::Response::Cors.apply r, origins: %w[https://app.example.com]
      _(r.headers['access-control-allow-origin']).must_be_nil
    end
  end

  describe 'preflight' do
    it 'halts with 204 + empty body when OPTIONS + ACRM are present' do
      r = build_response(request_method: 'OPTIONS', acrm: 'POST', origin: 'https://app.example.com')
      Lux::Response::Cors.apply r, :all
      _(r._status).must_equal 204
      _(r._body).must_equal ''
    end

    it 'does not halt on a normal request' do
      r = build_response(request_method: 'GET', origin: 'https://app.example.com')
      Lux::Response::Cors.apply r, :all
      _(r._status).must_be_nil
      _(r._body).must_be_nil
    end
  end

  describe 'symbol method list coercion' do
    it 'upcases symbol verbs' do
      r = build_response(origin: 'https://x.example')
      Lux::Response::Cors.apply r, origins: '*', methods: %i[get post]
      _(r.headers['access-control-allow-methods']).must_equal 'GET, POST'
    end
  end

  describe 'credentials' do
    it 'sets the header when explicit + non-wildcard origin matches' do
      r = build_response(origin: 'https://app.example.com')
      Lux::Response::Cors.apply r,
        origins: %w[https://app.example.com],
        credentials: true
      _(r.headers['access-control-allow-credentials']).must_equal 'true'
      _(r.headers['access-control-allow-origin']).must_equal 'https://app.example.com'
    end
  end
end
