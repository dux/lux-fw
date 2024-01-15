# renders pages without server

module Lux
  class Application
    module Render
      extend self

      # Alternative was to call render action
      # `Lux.app.new(path, full_opts).render.headers`
      # `Lux.render.post(path, params, rest_of_opts).headers`
      # `Lux.render.get('/search', params: { q: 'london' }, session: {user_id: 1} }).body`
      %i(get post delete patch put).each do |req_method|
        define_method req_method do |path, opts={}|
          Lux.app.new(path, opts.merge(method: req_method)).render
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
        c.send action

        Lux.current.response
      end

      # Lux.render.controller('main/cities#bar') { @city = City.last_updated }.body
      def template *args
        Lux::Template.render *args
      end

      # Lux.render.cell(:user, self, { product: @bar }).foo
      # Lux.render.cell(:user, self).foo
      # Lux.render.cell(:user, { product: @bar }).foo
      # Lux.render.cell(:user).foo @arg
      def cell name, *args
        opts    = args.last.is_a?(Hash) ? args.pop : {}
        context = args.shift
        Lux::ViewCell.get(name, context, opts)
      end
    end
  end
end

