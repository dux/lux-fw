module Lux
  module Lifecycle
    define_method(:request)  { Lux.ctx.request }
    define_method(:response) { Lux.ctx.response }
    define_method(:params)   { Lux.ctx.params }
    define_method(:nav)      { Lux.ctx.nav }
    define_method(:session)  { Lux.ctx.session }
    define_method(:user)     { Lux.ctx.user }

    define_method(:redirect_to) { |where, flash = {}| Lux.ctx.response.redirect_to where, flash }
  end
end
