# make cell available in helpers

class ViewCell < Lux::ViewCell
end

module HtmlHelper
  extend self

  def cell name=nil, args={}
    if name
      if name.is_a?(Array)
        # cell @boards.cards.all
        name.map { |el| cell el }.join(' ')
      elsif name.is_a?(Symbol)
        # cell(:card).render @card
        ViewCell.get(name, self, args)
      else
        # cell @card -> cell.card.render @card
        cell.send(name.class.to_s.tableize.singularize.to_sym).render name
      end
    else
      # cell.card.render @card
      ViewCell::Proxy.new(self)
    end
  end
end

# make cell available in controllers
module Lux
  class Controller
    def cell *args
      HtmlHelper.cell *args
    end
  end
end
