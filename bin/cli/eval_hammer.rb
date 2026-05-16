task :evaluate do
  desc 'Eval ruby string in context of Lux::Application'
  alt :e, :eval
  needs :app

  proc do |opts|
    require 'amazing_print'
    hammer :console, *opts[:args]
  end
end
