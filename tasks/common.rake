def invoke task, *args
  puts task.light_black
  Rake::Task[task].invoke(*args)
end
