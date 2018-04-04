def run(what)
  puts what.yellow
  system what
end

def tpool(list, parallel=6, &block)
  t = Thread.pool(parallel)
  for el in list
    t.process(el) { |o| block.call(o) }
  end
  t.shutdown
end

###

task :env do
  Bundler.require :default, ENV.fetch('RACK_ENV')
  require './config/application'
end

# task :default do
  # system 'rake -T'
  # ruby_path = `which ruby`
  # rake_path = `which rake`
  # puts `#{ruby_path} #{rake_path} -T`
  # tasks = `rake -T`.split("\n")
  # tasks.each_with_index do |el, i|
  #   num = i + 1
  #   puts "#{num.to_s.rjust(3)}. #{el}"
  # end
  # print "Execute task: "
  # val = STDIN.gets.chomp.to_s.to_i
  # task = tasks[val-1].to_s.split(/\s+#/).first
  # if val == 0
  # elsif task
  #   puts "Executing: #{task.yellow}"
  #   system task
  # else
  #   puts 'Taks not found'.red
  # end
# end

###

for file in Dir['%s/tasks/*.rake' % Lux.fw_root] + Dir['./**/*.rake']
  eval File.read file
end
