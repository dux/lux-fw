LuxCli.class_eval do
  desc :routes, 'Print routes'
  def routes
    require './config/application'

    # overload route methods to print routes
    ::Lux::Application.class_eval do
      def indent value=nil
        @indent ||= 0
        @indent += value if value
        '  ' * @indent
      end

      def show_route route, target
        route = route.keys.first if route.is_a?(Hash)

        route       = route.to_s
        controller  = nil

        if target.is_a?(String)
          target     = target.split('#')
          target[0] += '_controller'
          target[0]  = target[0].classify
          controller = target[0].constantize rescue nil
          target     = target.join(' # ')
        elsif target.is_a?(Array)

        else
          controller  = target
          target      = target
        end

        print indent
        route = route.to_s
        route = [@prefix, route].join('/') if @prefix
        route = '/%s' % route unless route.include?('/')
        route += '/*' unless target.include?('#')
        route = "#{@prefix}/*" if route .include?('#')
        print route.ljust(45 - indent.length)
        print target.ljust(45)

        if controller && !target.include?('#')
          puts
          for el in controller.instance_methods(false)
            print " #{route.to_s.sub('/*', '/')}#{el}".ljust(45)
            puts [target, el].join(' # ')
          end
        else
          puts
        end
      end

      def map obj, &block
        if @target
          target = @target.is_a?(String) && !@target.include?('#') ? @target + "##{obj}" : @target
          show_route obj, target
        elsif obj.is_a?(Hash)
          show_route obj.keys.first, obj.values.first
        elsif block_given?
          @target = obj
          yield
          @target = nil
        end
      end

      def namespace name
        name = ':%s' % name if name.is_a?(Symbol)
        @prefix = '%s/%s' % [@prefix, name]
        puts '%s (namespace)' % name.yellow
        indent 1
        yield
        indent -1
        @prefix = nil
      end
    end

    begin
      Lux::Application.render '/route-mock'
    rescue => e
      "#{e.class} - #{e.message}"
    end
  end
end
