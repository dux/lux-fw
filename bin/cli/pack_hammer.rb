require 'fileutils'
require 'find'
require 'pathname'
require 'shellwords'

# Build a deployable, symlink-flattened copy of the app under a cache dir,
# ready for rsync to production. Tracked files come from `git ls-files`, so
# everything in .gitignore (tmp, log, .gems, public/assets, secrets, .git)
# is excluded by definition. Gitignored-but-needed dirs are re-added via
# AUTO_INCLUDES; compiled assets are expected to be prepared beforehand.
#
# Lux plugin mounts (`lux mount`) are symlinks into plugins/<name>/mount/,
# kept out of git on purpose. Pack discovers those live links and ships their
# content as real files (rsync -L). User/app symlinks are never auto-added.
module LuxPack
  module_function

  DEFAULT_DEST  ||= './tmp/lux-app-cache'
  AUTO_INCLUDES ||= %w[.gems public/assets]   # gitignored, but needed on prod

  # Includes are copied wholesale (no per-dir git filter), so strip VCS/build
  # junk that local gem checkouts under ./.gems drag along.
  INCLUDE_EXCLUDES ||= %w[.git .gitignore node_modules tmp log coverage .DS_Store .build DerivedData]

  # Same skip set as Lux::Plugin::Mount::SCAN_SKIP_DIRS (+ pack noise dirs).
  MOUNT_SCAN_SKIP ||= %w[node_modules dist build tmp .next .git coverage .gems vendor public].freeze

  # Target path written by `lux mount` for every plugin-owned link.
  PLUGIN_MOUNT_TARGET ||= %r{/plugins/[^/]+/mount/}

  def build dest: DEFAULT_DEST, includes: [], dry: false
    raise Hammer::Error, 'not a git repo (no ./.git)' unless Dir.exist?('.git')
    raise Hammer::Error, 'refusing unsafe --dest' if dest.to_s.strip.empty? || %w[. /].include?(dest)

    files = `git ls-files -z`.split("\x0").reject(&:empty?)
    raise Hammer::Error, 'git ls-files returned nothing' if files.empty?

    # Drop tracked paths missing from the working tree (e.g. a file deleted
    # mid-refactor but not yet committed); rsync -L can't stat them and would
    # abort the whole deploy.
    missing, files = files.partition { |f| !File.exist?(f) }

    # Live lux-plugin mount symlinks only (not in git). User symlinks stay out.
    mounts = plugin_mount_symlinks
    files |= mounts

    AUTO_INCLUDES.each { |p| includes |= [p] if Dir.exist?(p) }
    includes.select! { |p| File.exist?(p) }

    puts 'Pack -> %s'         % dest.colorize(:yellow)
    puts 'Tracked files : %s' % files.size.to_s.colorize(:yellow)
    puts 'Plugin mounts : %s' % mounts.size.to_s.colorize(:yellow) if mounts.any?
    puts 'Skipped (gone): %s' % missing.size.to_s.colorize(:red) if missing.any?
    puts 'Includes      : %s' % (includes.empty? ? '-' : includes.join(', ')).colorize(:yellow)

    if dry
      puts '(dry run, nothing written)'.colorize(:light_black)
    else
      FileUtils.rm_rf dest
      FileUtils.mkdir_p dest

      # -L dereferences every symlink into a real file (local gems, plugin mounts)
      IO.popen(['rsync', '-aL', '--from0', '--files-from=-', './', dest + '/'], 'w') do |io|
        io.write files.join("\x0")
      end
      raise Hammer::Error, 'rsync failed' unless $?.success?

      # -R preserves each include's relative path (public/assets -> dest/public/assets)
      excludes = INCLUDE_EXCLUDES.flat_map { |p| ['--exclude', p] }
      includes.each { |path| system 'rsync', '-aLR', *excludes, path, dest + '/' }

      FileUtils.rm_f File.join(dest, '.gitignore')

      size = `du -sh #{dest} 2>/dev/null`.split("\t").first.to_s.strip
      puts 'Packed %s into %s' % [size.colorize(:yellow), dest.colorize(:green)]
    end

    warn_unsynced_links files, includes
  end

  # rsync -L bakes the *working-tree* state of every symlinked repo into the
  # pack, but CI rebuilds those gems/plugins by cloning their git remote at the
  # committed+pushed ref. So a linked repo that is dirty, has unpushed commits,
  # or has no upstream ships code that exists nowhere the CI can reach - the
  # pack and the CI build diverge. Surface those repos before deploy.
  def warn_unsynced_links files, includes
    app_top = git_toplevel('.')
    seen    = {}
    bad     = []

    linked_symlinks(files, includes).each do |link|
      target = (File.realpath(link) rescue nil) or next          # broken link
      top    = git_toplevel(File.directory?(target) ? target : File.dirname(target))
      next if top.empty? || top == app_top                       # not a repo / our own repo
      next if seen[top]                                          # one warning per repo
      seen[top] = true

      issues = repo_issues(top) or next                          # clean + synced -> skip
      bad << [link, top, issues]
    end

    return if bad.empty?

    puts
    puts 'WARNING: linked repos out of sync - CI builds committed+pushed state, not this:'.colorize(:red)
    bad.each do |link, top, issues|
      puts '  %s -> %s (%s)' % [link.colorize(:yellow), top.colorize(:light_black), issues.colorize(:red)]
    end
  end

  # Walk the app tree for symlinks whose resolved target lives under a lux
  # plugin mount/ tree. Those are created by `lux mount` and excluded from git
  # (machine-specific relative targets). User/app symlinks are ignored.
  def plugin_mount_symlinks
    paths = []
    Find.find('.') do |path|
      base = File.basename(path)
      if path != '.' && File.directory?(path) && MOUNT_SCAN_SKIP.include?(base)
        Find.prune
        next
      end
      next unless File.symlink?(path)

      target = resolve_symlink(path) or next
      next unless target.to_s.match?(PLUGIN_MOUNT_TARGET)
      next unless target.exist? # broken mount link -> skip

      paths << path.sub(%r{\A\./}, '')
    end
    paths
  end

  def resolve_symlink path
    raw = Pathname.new(File.readlink(path))
    raw = Pathname.new(path).dirname.join(raw) unless raw.absolute?
    raw.cleanpath
  rescue Errno::ENOENT, Errno::ELOOP
    nil
  end

  # Every symlink rsync -L will dereference: tracked symlinks plus any symlink
  # nested inside a wholesale-copied include dir (e.g. .gems/* -> local gems).
  def linked_symlinks files, includes
    links = files.select { |f| File.symlink?(f) }
    includes.each do |inc|
      next unless File.directory?(inc)
      links.concat `find #{Shellwords.escape(inc)} -type l 2>/dev/null`.split("\n").reject(&:empty?)
    end
    links.uniq
  end

  def git_toplevel dir
    `git -C #{Shellwords.escape(dir)} rev-parse --show-toplevel 2>/dev/null`.strip
  end

  # nil when the repo is committed, pushed and has an upstream; else a short
  # summary like "2 changed, 1 untracked, 3 unpushed".
  def repo_issues top
    cwd    = Shellwords.escape(top)
    issues = []

    lines     = `git -C #{cwd} status --porcelain 2>/dev/null`.lines
    untracked = lines.count { |l| l.start_with?('??') }
    changed   = lines.size - untracked
    issues << "#{changed} changed"     if changed.positive?
    issues << "#{untracked} untracked" if untracked.positive?

    upstream = `git -C #{cwd} rev-parse --abbrev-ref --symbolic-full-name @{upstream} 2>/dev/null`.strip
    if upstream.empty?
      issues << 'no upstream'
    else
      ahead = `git -C #{cwd} rev-list --count @{upstream}..HEAD 2>/dev/null`.strip.to_i
      issues << "#{ahead} unpushed" if ahead.positive?
    end

    issues.empty? ? nil : issues.join(', ')
  end
end

task :pack do
  desc 'Build a symlink-flattened, gitignore-clean app copy ready for rsync deploy'
  opt :dest,    alias: :d, type: :string,  default: LuxPack::DEFAULT_DEST, desc: 'Destination dir'
  opt :include, alias: :i, type: :string,  default: '',                    desc: 'Extra gitignored paths to bundle (comma-sep)'
  opt :dry_run, alias: :n, type: :boolean, default: false,                 desc: 'List what would be packed, write nothing'

  proc do |opts|
    LuxPack.build dest:     opts[:dest],
                  includes: opts[:include].to_s.split(',').map(&:strip).reject(&:empty?),
                  dry:      opts[:dry_run]
  end
end
