require 'whirly'

def invoke task, *args
  puts task.colorize(:light_black)
  Rake::Task[task].invoke(*args)
end

def run what
  puts what.colorize(:yellow)
  system what
end

def die what
  puts '%s (%s)' % [what.colorize(:red), caller[0]]
  exit
end

def info text
  puts '* %s' % text.colorize(:yellow)
end

def tpool list, parallel=6, &block
  t = Thread.pool(parallel)
  for el in list
    t.process(el) { |o| block.call(o) }
  end
  t.shutdown
end

###

task :env do
  require './config/env'
end

task :app do
  require './config/app'
end

task :default do
  require 'lux-fw'
  system Lux.fw_root.join('bin/lux').to_s
end

###

require 'bundler/setup'

Bundler.require :default, ENV.fetch('RACK_ENV')

tasks  = []
tasks += Dir['%s/tasks/*.rake' % Lux.fw_root]
tasks += Dir['./lib/**/*.rake']

for dir in Lux.plugin.folders
  tasks += Dir['%s/**/*.rake' % dir]
end

tasks.each do |file|
  load file
end

