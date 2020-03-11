# make cell available in helpers

class ViewCell < Lux::ViewCell
end

module HtmlHelper
  def cell name=nil, *args
    if name
      ViewCell.get(name, self, *args)
    else
      return @cell_base ||= ViewCell::Loader.new(self)
    end
  end
end

# make cell available in controllers
module Lux
  class Controller
    def cell name=nil
      name = if name
        name.to_s.classify
      else
        self.class.to_s.split('::').last.sub('Controller')
      end

      name.constantize.new(self, vars)
    end
  end
end
