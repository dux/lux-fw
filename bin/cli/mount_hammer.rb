# Mount only needs Lux.config[:plugins] + plugin folders; no app boot.
require_relative '../../lib/lux/plugin/plugin'
require_relative '../../lib/lux/plugin/mount'

task :mount do
  desc 'Symlink missing entries from each plugin\'s mount/ into the app root'
  opt :unlink, alias: :u, type: :boolean, default: false, desc: 'Unlink plugin-owned symlinks, then list user-added symlinks in the app'
  opt :list,   alias: :l, type: :boolean, default: false, desc: 'List all plugin mount entries and their status'
  opt :copy,   alias: :c, type: :boolean, default: false, desc: 'Copy plugin files into the app as real files instead of symlinks (self-contained deploy/Docker)'
  opt :clean,                type: :boolean, default: false, desc: 'Restore symlinks: reconvert copied files back to plugin symlinks'
  opt :git_rm,               type: :boolean, default: false, desc: 'Untrack mount symlinks (git rm --cached) so .git/info/exclude ignores them; commit to finalize'

  proc do |opts|
    if opts[:list]
      Lux::Plugin::Mount.print_list opts[:args].first
    elsif opts[:unlink]
      Lux::Plugin::Mount.unlink opts[:args].first
    elsif opts[:copy]
      Lux::Plugin::Mount.apply opts[:args].first, mode: :copy
    elsif opts[:clean]
      Lux::Plugin::Mount.apply opts[:args].first, mode: :symlink, git_rm: opts[:git_rm]
    else
      Lux::Plugin::Mount.apply opts[:args].first, git_rm: opts[:git_rm]
    end
  end
end

namespace :mount do
  task :list do
    desc 'List all plugin mount entries and their status'

    proc do |opts|
      Lux::Plugin::Mount.print_list opts[:args].first
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
    desc '(removed) use `lux mount -u PLUGIN`'

    proc do |opts|
      hint = 'lux mount -u %s' % (opts[:args].first || 'PLUGIN')
      raise Hammer::Error, 'mount:remove was removed - use: %s' % hint
    end
  end
end
