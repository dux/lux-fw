class MiniAssets::Asset::Css < MiniAssets::Asset
  def content_type
    'text/css'
  end

  def environment_prefix?
    true
  end

  def compile_scss
    compile_sass
  end

  def compile_sass
    node_sass = './node_modules/node-sass/bin/node-sass'
    node_opts = opts.production? ? '--output-style compressed' : '--source-comments'
    run! "#{node_sass} #{node_opts} '#{@source}' '#{@cache}'"
  end
end
