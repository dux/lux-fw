require_relative 'view_cell'

# make cell available in helpers
HtmlHelper.class_eval do
  def cell_assets
    Lux.ram_cache(:view_cell_public_assets) do
      out = []

      # css
      assets = '/assets/cell-assets.css'
      local  = Lux.root.join('public' + assets)

      if Lux.dev? && Lux.current.no_cache?
        local.write ViewCell.all_css
      end

      out.push '<link rel="stylesheet" href="%s?%s" />' % [assets, Crypt.sha1(local.read)]

      # js
      assets = '/assets/cell-assets.js'
      local  = Lux.root.join('public' + assets)

      if Lux.dev? && Lux.current.no_cache?
        local.write ViewCell.all_js
      end

      out.push '<script src="%s?%s"></script>' % [assets, Crypt.sha1(local.read)]
      out.join("\n")
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