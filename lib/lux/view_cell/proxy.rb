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
          # the file path is what the render trail is for (dev menu links it to
          # the editor), the class name is only a fallback for a cell we can't
          # find on disk
          files = ["app/cells/#{cell_name}/#{cell_name}_cell.rb", "app/cells/#{cell_name}_cell.rb"]
          file  = files.find { File.exist? _1 }

          Lux.current.files_in_use file || "#{cell_name.to_s.capitalize}Cell"
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
