LuxCli.class_eval do
  desc :memory, 'Show memory usage'
  def memory
    require 'memory_profiler'

    report = MemoryProfiler.report do
      require './config/app'
    end

    report.pretty_print retained_strings: 5, allocated_strings: 5#(to_file: "profile.txt")
  end
end
