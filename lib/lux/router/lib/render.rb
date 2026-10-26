# renders pages without server

module Lux
  class Router
    module Render
      extend self

      # Lux.render.get('/search', params: { q: 'london' }, session: { user_id: 1 }).body
      # Lux.render.post('/users', params: { name: 'x' }).headers
      VERBS ||= %i(get post delete patch put head)

      VERBS.each do |req_method|
        define_method req_method do |path, opts={}|
          Lux.router.new(path, opts.merge(method: req_method)).render_page
        end
      end

      # Carries the session from one render to the next, like a browser tab.
      #   c = Lux.render.client
      #   c.post '/login', params: { email: 'a@b.c' }
      #   c.get('/dashboard').status
      def client session = {}
        Client.new session
      end

      class Client
        attr_reader :session

        def initialize session = {}
          @session = session
        end

        VERBS.each do |req_method|
          define_method req_method do |path, opts={}|
            page = Render.public_send(req_method, path, opts.merge(session: @session.merge(opts[:session] || {})))
            @session = page.session
            page
          end
        end
      end

      # Lux.render.template(self, './app/views/foo.haml')
      def template *args
        Lux::Template.render *args
      end

      # Lux.render.cell(:user, self, { product: @bar }).foo
      # Lux.render.cell(:user, self).foo
      # Lux.render.cell(:user, { product: @bar }).foo
      # Lux.render.cell(:user).foo @arg
      def cell name, *args
        opts    = args.last.is_hash? ? args.pop : {}
        context = args.shift
        Lux::ViewCell.get(context, name, opts)
      end
    end
  end
end

