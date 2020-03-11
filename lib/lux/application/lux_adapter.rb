module Lux
  def app &block
    block ? Lux::Application.class_eval(&block) : Lux::Application
  end
  alias :application :app
end
