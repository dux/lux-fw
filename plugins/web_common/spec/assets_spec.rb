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
