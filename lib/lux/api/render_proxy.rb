# Proxy class for simplified more user friendly render
#
# UserApi.render.login(123, foo: 'bar') -> UserApi.render :login, id: 133, params: { foo: 'bar' }
#
# spec/tests/proxy_spec.rb
# UserApi.render.login(user: 'foo', pass: 'bar')
# CompanyApi.render.show(1)

module Lux
  class Api
    class RenderProxy
      def initialize api
        @api = api
      end

      def method_missing method_name, *args
        # if first param present, it must be resource ID
        api_id = args.shift unless args.first.is_hash?

        # convinience, second param is params hash, options follw
        params, opts = [args[0], args[1] || {}]

        # merge id and params to options
        opts.merge! params: params, id: api_id

        @api.render method_name, opts
      end
    end
  end
end
