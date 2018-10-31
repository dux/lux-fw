# export to all templates
# = asset 'www/index.scss'
# = asset 'www/index.coffee'
module HtmlHelper
  def asset_include path, opts={}
    raise ArgumentError.new("Path can't be empty") if path.empty?

    ext  = path.split('?').first.split('.').last
    type = ['css', 'sass', 'scss'].include?(ext) ? :style : :script
    type = :style if path.include?('fonts.googleapis.com')

    current.response.early_hints path, type

    if type == :style
      %[<link rel="stylesheet" href="#{path}" />]
    else
      %[<script src="#{path}"></script>]
    end
  end

  # builds full asset path based on resource extension
  # asset('js/main')
  # will render 'app/assets/js/main/index.coffee' as http://aset.path/assets/main-index-md5hash.js
  def asset file, opts={}
    opts = { dev_file: opts } unless opts.class == Hash

    # return joined assets if symbol given
    # = asset :main -> asset("css/main") + asset("js/main")
    return [asset("css/#{file}"), asset("js/#{file}")].join($/) if
      file.is_a?(Symbol)

    # return second link if it is defined and we are in dev mode
    return asset_include opts[:dev_file] if opts[:dev_file] && Lux.config(:compile_assets)

    # return internet links
    return asset_include file if file.starts_with?('/') || file.starts_with?('http')

    # return asset link in production or fail unless able
    unless Lux.config(:compile_assets)
      manifest = Lux.ram_cache('asset-manifest') { JSON.load Lux.root.join('public/manifest.json').read }
      mfile    = manifest['files'][file]

      raise 'Compiled asset link for "%s" not found in manifest.json' % file if mfile.empty?

      return asset_include(Lux.config.assets_root.to_s + mfile, opts)
    end

    # try to create list of incuded files and show every one of them
    data = LuxAssets.files(file).inject([]) do |total, asset|
      total.push asset_include '/compiled_asset/' + asset
    end

    data.map{ |it| it.sub(/^\s\s/,'') }.join("\n")
  end

end