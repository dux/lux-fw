require_relative 'view_cell'

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

  def cell name
    # cell @job -> cell(:job).render @job
    unless name.class == Symbol
      return ViewCell.get(name.class.to_s.underscore.to_sym, self).render name
    end

    view_cell = ViewCell.get(name, self)

    src = view_cell.method(:render).source_location[0].split(':').first
    Lux.current.files_in_use.push src.sub(Lux.root.to_s+'/', '')

    view_cell
  end

end

