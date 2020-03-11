require 'whirly'

def run what
  puts what.yellow
  system what
end

def die what
  puts '%s (%s)' % [what.red, caller[0]]
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
  require './config/environment'
end

task :app do
  require './config/application'
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

for dir in Lux.config.plugins
  tasks += Dir['%s/**/*.rake' % Lux.fw_root.join("plugins/#{dir}")]
end

tasks.each { |file| eval File.read file }
