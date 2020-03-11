LuxCli.class_eval do
  desc :routes, 'Print routes'
  def routes
    require './config/application'

    $total_routes = 0

    $indent = proc do |value, target=nil|
      $indent_val ||= 0
      $indent_val += value if value.is_a?(Numeric)

      if value && !value.is_a?(Numeric)
        $total_routes += 1 if target || value.to_s.include?('(call)')

        dotted = ('  ' * $indent_val) + value.to_s.white
        #ap [dotted.length, dotted.length % 4 - 3]
        to_shift = dotted.length % 3 - 2
        dotted += ' ' * to_shift.abs if to_shift < 0
        dotted += ('  .' * 25)
        out = dotted[0, 70] + target.to_s
        out = out.sub(/(\([^\)]+\))/) { |el| el.to_s.gray }
        out = out.gsub(' . ', ' . '.gray)
        puts out
      end
    end

    ###

    ::Lux.class_eval do
      def log what=nil
      end
    end

    ::Lux::Application::Routes::MagicRoutes.class_eval do
      def method_missing name, *args, &block
        $indent.call "/#{name}", args.first
      end
    end

    # overload route methods to print routes
    ::Lux::Application.class_eval do
      def error *args
        {}.to_ch
      end

      def call what
        $indent.call "#{what} (call)"
      end

      def root where
        $indent.call "/ (root)", where
      end

      def map what=nil
        return ::Lux::Application::Routes::MagicRoutes.new(self) unless what

        if block_given?
          what = what.is_a?(Symbol) ? "/:#{what} (#{what}_map)" : %{/#{what}}
          $indent.call what
          $indent.call 1
          yield
          $indent.call -1
        else
          if what.is_a?(String)
            $indent.call '%s (call)' % what
          elsif what.is_a?(Hash)
            if what.keys.first.is_a?(Array)
              what.keys.first.each { |el| $indent.call "/#{el}", what.values.first }
            else
              route = what.keys.first
              route = '/%s' % route unless route[0] == '/'
              $indent.call route, what.values.first
            end
          else
            $indent.call what.first
          end
        end
      end
    end

    Lux.render('/route-mock').info

    puts
    puts 'Unique routes: %s' % $total_routes
  end
end
