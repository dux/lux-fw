require_relative 'view_cell'

# make cell available in helpers
HtmlHelper.class_eval do
  def cell_assets
    Lux.ram_cache(:view_cell_public_assets) do
      assets = '/assets/cell-assets.css'
      local  = Lux.root.join('public' + assets)

      local.write ViewCell.all_css if Lux.dev? && Lux.current.no_cache?

      sha1 = Crypt.sha1 local.read

      '<link rel="stylesheet" href="%s?%s" />' % [assets, sha1]
    end
  end

  def cell name=nil, vars={}
    if name
      ViewCell.get(name, self, vars)
    else
      return @cell_base ||= ViewCell::Loader.new(self)
    end
  end
end

# make cell available in controllers
Lux::Controller.class_eval do
  def cell name=nil
    name = if name
      name.to_s.classify
    else
      self.class.to_s.split('::').last.sub('Controller')
    end

    name.constantize.new(self, vars)
  end
end