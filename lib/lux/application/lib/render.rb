module Lux
  class Application
    module Render
      extend self

      # Alternative was to call render action
      # `Lux.app.new(path, full_opts).info`
      # `Lux.render.post(path, params, rest_of_opts).info`
      # `Lux.render.get('/search', { q: 'london' }, { session: {user_id: 1} }).info`
      %i(get post delete patch put).each do |req_method|
        define_method req_method do |path, params={}, opts={}|
          Lux.app.new path, opts.merge(request_method: :get, query_string: params)
        end
      end

      # Render controller action without routes, pass a block to yield before action call.
      # `Lux.render.controller('main/cities#foo').body`
      # `Lux.render.controller('main/cities#foo') { @city = City.last_updated }.body`
      def controller klass, &block
        klass, action = klass.split('#')

        klass = (klass+'Controller').classify.constantize if klass.is_a?(String)
        c = klass.new
        c.instance_exec &block if block

        catch :done do
          c.send action
        end

        Lux.current.response
      end

      # Lux.render.controller('main/cities#bar') { @city = City.last_updated }.body
      def template *args
        Lux::Template.render *args
      end
    end
  end
end

