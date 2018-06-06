require_relative 'widget'

HtmlHelper.class_eval do

  def widget_assets *widgets
    return if request.xhr?

    '<style>%s</style>' % Widget.all_css
  end

end

