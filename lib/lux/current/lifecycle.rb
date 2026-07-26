module Lux
  module Lifecycle
    define_method(:current)  { Lux.current }
    define_method(:request)  { lux.request }
    define_method(:response) { lux.response }
    define_method(:params)   { lux.params }
    define_method(:nav)      { lux.nav }
    define_method(:session)  { lux.session }
    define_method(:user)     { lux.user }

    define_method(:redirect_to) { |where, flash = {}| lux.response.redirect_to where, flash }
  end
end
