require_relative './view_cell'
require_relative './proxy'

# enables shortcut
#   FooCell.new(self).bar -> cell.foo.bar

Lux::Template::Helper.include Lux::ViewCell::ProxyMethod
Lux::Router.include Lux::ViewCell::ProxyMethod
