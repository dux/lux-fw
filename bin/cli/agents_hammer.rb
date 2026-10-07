require_relative 'lib/agents_md'

task :agents do
  desc 'Write or refresh the lux-fw docs pointer in ./AGENTS.md'

  proc do
    result = LuxAgentsMd.write(Dir.pwd, Lux.fw_root.to_s)
    say.green 'AGENTS.md %s' % result
  end
end
