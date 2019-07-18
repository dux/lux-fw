module Lux::DelayedJob::Inline
  extend self

  def write func, data
    Lux::DelayedJob.call func, data
  end

  def read
  end

  def process
    puts 'Lux::DelayedJob::Memory executes jobs as they are added. No nedd to process'
    sleep 1_000_000_000
  end
end