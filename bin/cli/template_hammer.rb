task :template do
  desc 'Parse single file and replace $VAR with ENV values'

  proc do |opts|
    path = opts[:args].first
    error 'Usage: lux template PATH' unless path

    ENV['ROOT'] = `pwd`.chomp

    data = File.read(path)
    data = data.gsub(/\$([A-Z]+)/) { ENV[$1] || raise('ENV variable "%s" not defined' % $1) }
    puts data
  end
end
