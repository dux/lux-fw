require 'test_helper'
require 'fileutils'
require 'tmpdir'

require_relative '../../web_common/load/assets/cdn_asset'
require_relative '../load/favicon'

describe Favicon do
  def in_app
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { yield dir }
    end
  end

  def seed
    FileUtils.mkdir_p 'public'
    FileUtils.cp Favicon::SEED, Favicon::SOURCE
  end

  def render_html icon: nil
    previous, Lux.config[:app] = Lux.config[:app], { name: 'T' }.to_lux_hash
    el = Lux::Current.new(Rack::MockRequest.env_for('/')).browser.html
    el.render do
      el.icon icon unless icon.nil?
      el.body { 'x' }
      ''
    end
  ensure
    Lux.config[:app] = previous
  end

  it 'builds a png-in-ico and the touch icon from the svg' do
    in_app do
      seed
      Favicon.build!

      ico = File.binread(Favicon::ICO)
      _(ico[0, 6].unpack('v3')).must_equal [0, 1, 1]
      _(ico[22, 8]).must_equal "\x89PNG\r\n\x1A\n".b
      _(ico[14, 4].unpack1('V')).must_equal ico.bytesize - 22
      _(File.binread("public/assets/#{Favicon::TOUCH}")[0, 8]).must_equal "\x89PNG\r\n\x1A\n".b
      _(Favicon.stale?).must_equal false
    end
  end

  it 'seeds a missing svg and rebuilds stale outputs' do
    in_app do
      capture_stdout { Favicon.refresh! }
      _(File.read(Favicon::SOURCE)).must_equal File.read(Favicon::SEED)
      _(File.exist?(Favicon::ICO)).must_equal true

      FileUtils.rm "public/assets/#{Favicon::TOUCH}"
      _(Favicon.stale?).must_equal true
      Favicon.refresh!
      _(Favicon.stale?).must_equal false
    end
  end

  it 'emits the icon links, versioned by the svg content' do
    in_app do
      _(Favicon.tags).must_equal []

      seed
      Favicon.build!
      v = File.read(Favicon::SOURCE).sha1[0, 8]
      tags = Favicon.tags

      _(tags[0]).must_equal %[<link rel="icon" href="/favicon.ico?v=#{v}" sizes="32x32" />]
      _(tags[1]).must_equal %[<link rel="icon" href="/favicon.svg?v=#{v}" type="image/svg+xml" />]
      _(tags[2]).must_match %r{<link rel="apple-touch-icon" href="/assets/apple-touch-icon\.png\?}
    end
  end

  it 'puts the links in render_html unless el.icon false' do
    in_app do
      seed
      Favicon.build!

      _(render_html).must_include 'rel="apple-touch-icon"'
      refute_includes render_html(icon: false), 'favicon'
    end
  end

  it 'puts the links in lux.header.render too' do
    in_app do
      seed
      Favicon.build!

      header = Lux::Current.new(Rack::MockRequest.env_for('/')).header
      header.site_name 'T'
      _(header.render).must_include 'href="/favicon.svg?v='
    end
  end
end
