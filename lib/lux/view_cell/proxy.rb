require_relative './view_cell'

module Lux
  class ViewCell
    # proxy loader class
    # cell.user.foo -> cell(:user).foo
    class Proxy
      def initialize parent
        @parent = parent
      end

      def method_missing cell_name, vars = {}
        if Lux.env.dev?
          name = "#{cell_name.to_s.capitalize}Cell"
          for f in ["app/cells/#{cell_name}/#{cell_name}_cell.rb", "app/cells/#{cell_name}_cell.rb"]
            name += " - #{f}" if File.exist?(f)
          end
          Lux.current.files_in_use name
        end

        Lux::ViewCell.get(@parent, cell_name, vars)
      end
    end

    # adapter will inject this
    module ProxyMethod
      def cell *args
        Lux::ViewCell.cell self, *args
      end
    end
  end
end
