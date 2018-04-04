class MiniAssets::Base::JavaScript < MiniAssets::Base
  def asset_class
    MiniAssets::Asset::Js
  end

  def join_string
    ";\n"
  end

  def render_production
    run! './node_modules/minifier/index.js --no-comments -o "%{file}" "%{file}"' % { file: @target }
  end
end