require_relative './view_cell'
require_relative './proxy'

# enables shortcut
#   FooCell.new(self).bar -> cell.foo.bar

[
  'ActionView::Base',
  'ActionController::Base',
  'Lux::Template::Helper',
  'Lux::Controller',
  'Sinatra::Application'
].each do |klass|
  if Object.const_defined?(klass)
    klass.constantize.include Lux::ViewCell::ProxyMethod
  end
end
