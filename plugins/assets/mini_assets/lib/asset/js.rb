class MiniAssets::Asset::Js < MiniAssets::Asset
  def content_type
    'text/javascript'
  end

  def compile_coffee
    coffee_path = './node_modules/coffee-script/bin/coffee'
    coffee_opts = opts.production? ? '-cp' : '-Mcp --no-header'

    run! "#{coffee_path} #{coffee_opts} '#{@source}' > '#{@cache}'"

    data = @cache.read
    data = data.gsub(%r{//#\ssourceURL=[\w\-\.\/]+/app/assets/}, '//# sourceURL=/raw_asset/')

    @cache.write data
  end
end
