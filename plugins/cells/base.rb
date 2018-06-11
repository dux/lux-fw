require_relative 'view_cell'

HtmlHelper.class_eval do

  def cell_assets *cells
    return if request.xhr?

    '<style>%s</style>' % ViewCell.all_css
  end

  def cell name
    # cell @job -> cell(:job).render @job
    unless name.class == Symbol
      return cell(name.class.to_s.underscore.to_sym).render name
    end

    w = ('%sCell' % name.to_s.classify).constantize
    w = w.new self

    src = w.method(:render).source_location[0].split(':').first
    Lux.current.files_in_use.push src.sub(Lux.root.to_s+'/', '')

    w
  end

end

