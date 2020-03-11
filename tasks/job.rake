namespace :job do
  desc 'Start delayed job que tasks Server (NSQ, Faktory, ...)'
  task start: :app do
    Lux.delay.start
  end

  desc 'Process delayed job que tasks (NSQ, Faktory, ...)'
  task process: :app do
    Lux.delay.process
  end
end

