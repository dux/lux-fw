module LuxBenchmark
  module_function

  def draw_load_speed(what)
    time = Benchmark.realtime { yield }
    puts "#{(time * 1000).to_i.to_s.rjust(4)} ms #{what}"
  end
end

task :benchmark do
  desc 'Benchmark app boot time'

  proc do |_opts|
    require 'benchmark'

    def Kernel.require(what)
      LuxBenchmark.draw_load_speed(what) { super }
    end

    LuxBenchmark.draw_load_speed('./config/env.rb') { require './config/env'; puts '     --' }
    LuxBenchmark.draw_load_speed('./config/app.rb') { require './config/app' }
  end
end
