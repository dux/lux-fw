require 'test_helper'
require_relative '../../plugins/web_common/load/assets/cdn_asset'

describe CdnAsset do
  it 'expands a legacy hash-only manifest value into a fingerprinted filename' do
    file = CdnAsset.send(:normalize_manifest_file, 'auto-main.js', 'fb41176a')

    _(file).must_equal 'auto-main.fb41176a.js'
  end

  it 'keeps a current full manifest filename unchanged' do
    file = CdnAsset.send(
      :normalize_manifest_file,
      'auto-main.js',
      'auto-main.fb41176a.js'
    )

    _(file).must_equal 'auto-main.fb41176a.js'
  end
end
