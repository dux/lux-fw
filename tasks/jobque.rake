namespace :jobque do
  desc 'Process job que tasks (NSQ, Faktory, ...)'
  task process: :app do
    Lux.delay.process
  end
end

