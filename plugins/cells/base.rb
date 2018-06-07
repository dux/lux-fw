require_relative 'html_cell'

HtmlHelper.class_eval do

  def cell_assets *cells
    return if request.xhr?

    '<style>%s</style>' % HtmlCell.all_css
  end

end

