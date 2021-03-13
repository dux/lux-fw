def draw_load_speed what
  time = Benchmark.realtime { yield }
  puts "#{(time * 1000).to_i.to_s.rjust(4) } ms #{what}"
end

LuxCli.class_eval do
  desc :benchmark, 'Benchmark app boot time'
  def benchmark
    require "benchmark"

    def Kernel.require what
      draw_load_speed(what) { super }
    end

    draw_load_speed('./config/env.rb') { require './config/env'; puts '     --'}
    draw_load_speed('./config/app.rb') { require './config/app' }
  end
end
