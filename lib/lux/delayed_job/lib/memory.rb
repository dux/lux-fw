module Lux::DelayedJob::Memory
  extend self

  @jobs = []

  def push data
    @jobs.push data

    # delayed jobs in memory are resolved asap
    Thread.new { true while pop }
  end

  def pop
    @jobs.shift
  end
end