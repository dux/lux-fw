require 'fileutils'

# Build a deployable, symlink-flattened copy of the app under a cache dir,
# ready for rsync to production. Tracked files come from `git ls-files`, so
# everything in .gitignore (tmp, log, .gems, public/assets, secrets, .git)
# is excluded by definition. Gitignored-but-needed dirs are re-added via
# AUTO_INCLUDES; compiled assets are expected to be prepared beforehand.
module LuxPack
  module_function

  DEFAULT_DEST  ||= './tmp/lux-app-cache'
  AUTO_INCLUDES ||= %w[.gems public/assets]   # gitignored, but needed on prod

  # Includes are copied wholesale (no per-dir git filter), so strip VCS/build
  # junk that local gem checkouts under ./.gems drag along.
  INCLUDE_EXCLUDES ||= %w[.git .gitignore node_modules tmp log coverage .DS_Store]

  def build dest: DEFAULT_DEST, includes: [], dry: false
    raise Hammer::Error, 'not a git repo (no ./.git)' unless Dir.exist?('.git')
    raise Hammer::Error, 'refusing unsafe --dest' if dest.to_s.strip.empty? || %w[. /].include?(dest)

    files = `git ls-files -z`.split("\x0").reject(&:empty?)
    raise Hammer::Error, 'git ls-files returned nothing' if files.empty?

    AUTO_INCLUDES.each { |p| includes |= [p] if Dir.exist?(p) }
    includes.select! { |p| File.exist?(p) }

    puts 'Pack -> %s'         % dest.colorize(:yellow)
    puts 'Tracked files : %s' % files.size.to_s.colorize(:yellow)
    puts 'Includes      : %s' % (includes.empty? ? '-' : includes.join(', ')).colorize(:yellow)

    return puts('(dry run, nothing written)'.colorize(:light_black)) if dry

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
