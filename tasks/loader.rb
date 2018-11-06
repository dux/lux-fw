def run what
  puts what.yellow
  system what
end

def die what
  puts '%s (%s)' % [what.red. caller[0]]
  exit
end

def info text
  puts '* %s' % text.yellow
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
  require './config/application'
end

task :default do
  puts '"rake -T" to show all tasks'
end

###

require 'bundler/setup'
require 'dotenv'

Dotenv.load
Bundler.require :default, ENV.fetch('RACK_ENV')

tasks  = []
tasks += Dir['%s/tasks/*.rake' % Lux.fw_root]
tasks += Dir['./lib/**/*.rake']

for dir in Lux.plugin.loaded.map(&:folder)
  tasks += Dir['%s/**/*.rake' % dir]
end

tasks.each { |file| eval File.read file }
