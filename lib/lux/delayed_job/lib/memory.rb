module Lux::DelayedJob::Memory
  extend self

  @@JOBS = []

  def push(data)
    @@JOBS.push data
    Thread.new { true while Lux::DelayedJob.pop }
  end

  def pop
    @@JOBS.shift
  end
end