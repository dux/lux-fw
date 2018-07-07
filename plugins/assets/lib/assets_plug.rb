# plug :local_assets
# /compiled_asset/www/js/pjax.coffee
# /raw_asset/www/js/pjax.coffee
Lux.app do
  def lux_assets_plug
    # only allow clear in dev
    # clear assets every 4 seconds max
    if Lux.current.no_cache? && Lux.config(:compile_assets)

      Lux.cache.fetch('lux-clear-assets', ttl: 4, log: false, force: false) do
        puts '* Clearing assets from ./tmp/assets'.yellow
        `rm -rf ./tmp/assets && mkdir ./tmp/assets`
        true
      end
    end

    path = nav.rest.join('/')

    if nav.root == 'compiled_asset'
      asset = MiniAssets::Asset.call(path)
      current.response.content_type asset.content_type
      current.response.body asset.render

    elsif nav.root == 'raw_asset'
      Lux.error "You can watch raw files only in development" unless Lux.dev?

      file = Lux.root.join('app/assets/%s' % path)
      body file.exist? ? file.read : "error: File not found"
    end
  end
end