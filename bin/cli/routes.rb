LuxCli.class_eval do
  desc :routes, 'Print routes'
  def routes
    require './config/application'

    # overload route methods to print routes
    ::Lux::Application.class_eval do
      def error *args
        {}.h
      end

      def indent value=nil
        @indent ||= 0
        @indent += value if value
        '  ' * @indent
      end

      def show_route route, target
        route = route.keys.first if route.is_a?(Hash)

        controller  = nil

        if route.is_a?(Array)
          for rut in route
            rut = rut.to_s
            rut = [@prefix, rut].join('/') if @prefix
            print "#{indent}/#{rut}".ljust(50)
            puts ["#{target}_controller".classify, rut].join ' # '
          end
          return
        elsif target.is_a?(String)
          target     = target.split('#')
          target[0] += '_controller'
          target[0]  = target[0].classify
          controller = target[0].constantize rescue nil
          target     = target.join(' # ')
        else
          controller  = target
          target      = target
        end

        route = route.to_s
        route = [@prefix, route].join('/') if @prefix
        route = '/%s' % route unless route.include?('/')
        route += '/*' unless target.include?('#')
        route = "#{@prefix}/*" if route .include?('#')

        print "#{indent}#{route}".ljust(50)
        print target.ljust(50)

        if controller && !target.include?('#')
          puts
          for el in controller.instance_methods(false)
            print "  #{route.to_s.sub('/*', '/').gsub('//', '/')}#{el}".ljust(50)
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
        elsif obj.is_a?(Array)
          show_route obj[0], obj[1]
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
        puts '%s ->(namespace block)' % name.yellow
        indent 1
        yield
        indent -1
        @prefix = nil
      end
    end

    begin
      Lux.app.render '/route-mock'
    rescue => e
      "#{e.class} - #{e.message}"
    end
  end
end
