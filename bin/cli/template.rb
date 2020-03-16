LuxCli.class_eval do
  desc :template, 'Parse single file and replace end $VAR with values'
  def template path
    ENV['ROOT'] = `pwd`.chomp

    data = File.read path
    data = data.gsub(/\$([A-Z]+)/) { ENV[$1] || raise('ENV variable "%s" not defined' % $1) }
    puts data
  end
end
