# export to all templates
# = asset 'www/index.scss'
# = asset 'www/index.coffee'
module HtmlHelper
  def asset_include path
    raise ArgumentError.new("Path can't be empty") if path.empty?

    url = if path.starts_with?('/') || path.include?('//')
      path
    else
      '/compiled_asset/%s' % path
    end

    ext = url.split('?').first.split('.').last

    if ['coffee', 'js'].include?(ext)
      %[<script src="#{url}"></script>]
    else
      %[<link rel="stylesheet" href="#{url}" />]
    end
  end

  # builds full asset path based on resource extension
  # asset('main/index.coffee')
  # will render 'app/assets/main/index.coffee' as http://aset.path/assets/main-index-md5hash.js
  def asset file, dev_file=nil
    # return second link if it is defined and we are in dev mode
    return asset_include dev_file if dev_file && Lux.dev?

    # return internet links
    return asset_include file if file.starts_with?('/') || file.starts_with?('http')

    # return asset link in production or faile unless able
    unless Lux.config(:compile_assets)
      @@__asset_menifest ||= MiniAssets::Manifest.new
      mfile = @@__asset_menifest.get(file)
      raise 'Compiled asset link for "%s" not found in manifest.json' % file if mfile.empty?
      return asset_include Lux.config.assets_root.to_s + mfile
    end

    # try to create list of incuded files and show every one of them
    data = []
    asset = MiniAssets.new file

    for file in asset.files
      data.push asset_include file
    end

    data.join($/)
  end
end