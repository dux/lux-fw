require 'test_helper'
require 'openssl'

# PdfController is a mount/ file - it subclasses the host's FrontendController
# and is normally resolved from the plugin mount by the app. Stand that parent in so
# the controller can be loaded here, then test the part that has no app in it:
# the signed-URL contract.
#
# The flow being pinned: a request to /pdf/<page>.pdf signs the canonical path
# and hands the URL to a headless browser, which fetches /pdf/<page>?s=<sig>&e=<expiry>
# unauthenticated. The signature is built in one request and verified in
# another, so it has to be identical across both - and stable against whatever
# load_models or an app before-filter did to nav.path in between.
FrontendController ||= Class.new(Lux::Controller)

module PdfGenerator; end unless defined?(PdfGenerator)

require_relative '../mount/app/controllers/pdf_controller.rb'

# User.current is what Lux::Current#user reads; nobody is logged in here, which
# is the case the signature exists for.
unless defined?(User)
  User = Class.new do
    def self.current; nil; end
  end
end

describe PdfController do
  SECRET ||= 'pdf-spec-secret'

  before do
    @was_secret = Lux.config.key?(:secret) ? Lux.config[:secret] : nil
    Lux.config[:secret] = SECRET
  end

  after do
    Lux.config[:secret] = @was_secret
  end

  # PdfController#pdf_path is private - it is internal to the controller, and
  # this spec is asserting the contract it upholds.
  def pdf_path_for url
    Lux::Current.new url
    PdfController.new.send(:pdf_path)
  end

  describe '#pdf_path' do
    it 'is the request path' do
      _(pdf_path_for('http://test/pdf/demo')).must_equal '/pdf/demo'
    end

    # the whole point - the .pdf request and the HTML request it triggers must
    # sign the same string
    it 'is identical with and without the .pdf format suffix' do
      _(pdf_path_for('http://test/pdf/demo.pdf')).must_equal pdf_path_for('http://test/pdf/demo')
    end

    it 'survives load_models rewriting the ref segment out of nav.path' do
      ref = Lux::Utils::Ref.generate
      Lux::Current.new "http://test/pdf/travel_orders/#{ref}"

      before = PdfController.new.send(:pdf_path)
      Lux.current.nav.map_path                    # what pdf routes.rb does
      after  = PdfController.new.send(:pdf_path)

      _(Lux.current.nav.path.last).must_be_kind_of Lux::Application::Nav::Base
      _(after).must_equal before
      _(after).must_equal "/pdf/travel_orders/#{ref}"
    end

    it 'survives an app before-filter rewriting nav.path' do
      Lux::Current.new 'http://test/pdf/salary-runs/abc'
      before = PdfController.new.send(:pdf_path)

      Lux.current.nav.path.map! { |el| el.to_s.tr('-', '_') }   # a set_nav_ref style filter

      _(PdfController.new.send(:pdf_path)).must_equal before
    end
  end

  describe '.sign' do
    EXPIRES ||= 2_000_000_000

    it 'is stable for the same path and expiry' do
      _(PdfController.sign('/pdf/demo', EXPIRES)).must_equal PdfController.sign('/pdf/demo', EXPIRES)
    end

    it 'differs per path' do
      _(PdfController.sign('/pdf/demo', EXPIRES)).wont_equal PdfController.sign('/pdf/other', EXPIRES)
    end

    it 'differs per expiry' do
      _(PdfController.sign('/pdf/demo', EXPIRES)).wont_equal PdfController.sign('/pdf/demo', EXPIRES + 1)
    end

    it 'depends on the app secret' do
      first = PdfController.sign('/pdf/demo', EXPIRES)
      Lux.config[:secret] = 'a-different-secret'
      _(PdfController.sign('/pdf/demo', EXPIRES)).wont_equal first
    end
  end

  describe '#verify_access!' do
    def verify url
      Lux::Current.new url
      PdfController.new.send(:verify_access!)
    end

    def later = Time.now.to_i + 60

    # the real two-request round trip: sign on /pdf/demo.pdf, verify on /pdf/demo
    it 'accepts the signature minted by the .pdf request' do
      Lux::Current.new 'http://test/pdf/demo.pdf'
      expires = later
      signed  = PdfController.sign(PdfController.new.send(:pdf_path), expires)

      verify "http://test/pdf/demo?s=#{signed}&e=#{expires}"
    end

    it 'rejects a signature for a different path' do
      signed = PdfController.sign('/pdf/other', later)
      _{ verify "http://test/pdf/demo?s=#{signed}&e=#{later}" }.must_raise Lux::Error
    end

    it 'rejects an expired signature' do
      expires = Time.now.to_i - 1
      signed  = PdfController.sign('/pdf/demo', expires)
      _{ verify "http://test/pdf/demo?s=#{signed}&e=#{expires}" }.must_raise Lux::Error
    end

    it 'rejects a signature whose expiry was pushed out' do
      signed = PdfController.sign('/pdf/demo', Time.now.to_i - 1)
      _{ verify "http://test/pdf/demo?s=#{signed}&e=#{later}" }.must_raise Lux::Error
    end

    # a signature only admits the HTML page; the PDF needs a signed-in user
    it 'rejects a signature on the .pdf itself' do
      expires = later
      signed  = PdfController.sign('/pdf/demo', expires)
      _{ verify "http://test/pdf/demo.pdf?s=#{signed}&e=#{expires}" }.must_raise Lux::Error
    end

    it 'rejects a missing signature' do
      _{ verify 'http://test/pdf/demo' }.must_raise Lux::Error
    end

    it 'rejects an empty signature' do
      _{ verify "http://test/pdf/demo?s=&e=#{later}" }.must_raise Lux::Error
    end
  end
end
