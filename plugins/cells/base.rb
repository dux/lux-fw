Lux.plugin 'html'

require_relative 'view_cell'

# make cell available in helpers
HtmlHelper.class_eval do
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