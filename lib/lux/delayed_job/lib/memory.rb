module Lux::DelayedJob::Memory
  extend self

  @jobs = []

  def push *args
    @jobs.push data

    # delayed jobs in memory are resolved asap
    Thread.new { true while pop }
  end

  def process
    puts 'Lux::DelayedJob::Memory executes jobs as they are added. No nedd to process'
    sleep 1_000_000_000
  end
end