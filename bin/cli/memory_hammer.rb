define :memory do
  desc 'Show memory usage'

  proc do |_opts|
    require 'memory_profiler'

    report = MemoryProfiler.report do
      require './config/app'
    end

    report.pretty_print retained_strings: 5, allocated_strings: 5
  end
end
