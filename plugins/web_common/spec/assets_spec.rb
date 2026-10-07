require 'test_helper'
require 'fileutils'
require 'tmpdir'

require_relative '../load/assets/cdn_asset'

describe 'el.assets' do
  it 'renders css then js per name, skipping missing files' do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p "#{dir}/public/assets"
      %w[app.css app.js admin.css].each { File.write "#{dir}/public/assets/#{_1}", '' }
      el = Lux::Current.new(Rack::MockRequest.env_for('/')).browser.html
      tags = Dir.chdir(dir) { el.assets(:app, :admin) }.split("\n")
      _(tags.size).must_equal 3
      _(tags[0]).must_match %r{<link .*href="/assets/app\.css\?}
      _(tags[1]).must_match %r{<link .*href="/assets/admin\.css\?}
      _(tags[2]).must_match %r{<script src="/assets/app\.js\?}
    end
  end
end

describe 'CdnAsset.path' do
  it 'returns the stamped local url, or nil when the asset is not built' do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p "#{dir}/public/assets"
      File.write "#{dir}/public/assets/icon.png", ''

      Dir.chdir(dir) do
        _(CdnAsset.path('icon.png')).must_match %r{\A/assets/icon\.png\?\w+\z}
        _(CdnAsset.path('missing.png')).must_be_nil
      end
    end
  end
end

describe 'CdnAsset manifest' do
  it 'writes fingerprinted names and lists the assets:upload pairs' do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p "#{dir}/public/assets"
      File.write "#{dir}/public/assets/app.css", 'body{}'
      File.write "#{dir}/public/assets/app.js", 'x=1'
      File.write "#{dir}/public/assets/.gitkeep", ''

      Dir.chdir(dir) do
        CdnAsset.write_manifest
        manifest = JSON.parse(File.read('./public/manifest.json'))
        _(manifest.keys).must_equal %w[app.css app.js]
        _(manifest['app.css']).must_equal "app.#{'body{}'.md5[0, 8]}.css"
        _(CdnAsset.uploads).must_equal [
          ['./public/assets/app.css', "assets/#{manifest['app.css']}"],
          ['./public/assets/app.js',  "assets/#{manifest['app.js']}"],
        ]
      end
    end
  end

  it 'refuses to list uploads before a build' do
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { _{ CdnAsset.uploads }.must_raise RuntimeError }
    end
  end
end
