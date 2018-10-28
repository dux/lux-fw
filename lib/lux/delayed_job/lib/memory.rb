module Lux::DelayedJob::Memory
  extend self

  @jobs = []

  def push(data)
    @jobs.push data
    Thread.new { true while Lux::DelayedJob.pop }
  end

  def pop
    @jobs.shift
  end
end