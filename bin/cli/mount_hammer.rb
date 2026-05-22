# Mount only needs Lux.config[:plugins] + plugin folders; no app boot.
require_relative '../../lib/lux/plugin/plugin'
require_relative '../../lib/lux/plugin/mount'

task :mount do
  desc 'Symlink files from each configured plugin\'s mount/ into the app root'

  proc do |opts|
    Lux::Plugin::Mount.apply opts[:args].first
  end
end

namespace :mount do
  task :list do
    desc 'List all plugin mount entries and their status'

    proc do |opts|
      entries = Lux::Plugin::Mount.list opts[:args].first
      if entries.empty?
        puts 'No plugin mounts found'
      else
        entries.each { |e| puts '  %-9s %-12s %s' % [e.status, e.plugin, e.dst.to_s.sub(Lux.root.to_s + '/', '')] }
      end
    end
  end

  task :doctor do
    desc 'Diagnose plugin mounts; exits non-zero if unhealthy'
    opt :fix, type: :boolean, default: false, desc: 'Repair unhealthy entries via mount apply'

    proc do |opts|
      entries = Lux::Plugin::Mount.doctor fix: opts[:fix]
      exit 1 if entries.any? { _1.status != :ok && _1.status != :linked }
    end
  end

  task :remove do
    desc 'Unlink files mounted by PLUGIN'

    proc do |opts|
      name = opts[:args].first
      raise Hammer::Error, 'usage: lux mount:remove PLUGIN' unless name
      Lux::Plugin::Mount.remove name
    end
  end
end
