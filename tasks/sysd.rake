desc 'Call bin/sysd to manage app systemd service'
task :sysd do
  system 'bin/sysd'
end
