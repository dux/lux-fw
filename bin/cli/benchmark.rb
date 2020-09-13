LuxCli.class_eval do
  desc :benchmark, 'Benchmark app boot time'
  def benchmark
    require "benchmark"

    def Kernel.require what
      time = Benchmark.realtime { super }

      if time > 0.001
        puts "#{(time * 1000).to_i.to_s.rjust(4) } ms #{what}"
      end
    end

    require './config/application'
  end
end
