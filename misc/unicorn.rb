# set path to application
app_dir = File.expand_path("../..", __FILE__)
working_directory app_dir

# Set unicorn options
worker_processes 10
preload_app true
timeout 20

# Set up socket location
listen "127.0.0.1:3000", :tcp_nopush => true
listen "#{app_dir}/tmp/unicorn.sock", :backlog => 512

# Logging
stderr_path "#{app_dir}/log/unicorn.stderr.log"
stdout_path "#{app_dir}/log/unicorn.stdout.log"

# Set master PID location
pid "#{app_dir}/tmp/unicorn.pid"

worker_processes 5
timeout 15

preload_app true

GC.respond_to?(:copy_on_write_friendly=) and GC.copy_on_write_friendly = true

check_client_connection false

before_exec do |server|
end

before_fork do |server, worker|
end

after_fork do |server, worker|
end