ARGV[0] = 'eval' if ARGV[0] == 'e'

LuxCli.class_eval do
  desc :evaluate, 'Eval ruby string in context of Lux::Application'
  def evaluate *args
    require 'amazing_print'
    require './config/application'

    Lux.info 'Warning: Use lux c *args'
    console *args
  end
end
