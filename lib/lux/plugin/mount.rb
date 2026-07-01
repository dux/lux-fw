# File-level symlink manager for plugin `mount/` directories.
#
# A plugin can ship a `mount/` folder that mirrors the application root.
# Every leaf file under `mount/` is symlinked into the app at the matching
# relative path. Directories are recreated as real dirs in the app so two
# plugins may safely share the same parent directory.
#
# Symlinks are relative. Apply is idempotent and silently rewrites stale
# links from the *same* plugin (handles gem path drift between machines).
# Foreign files and cross-plugin collisions are reported, never overwritten.

require 'fileutils'
require 'find'

# Mount registers a Descriptor mixin into Plugin::DESCRIPTOR_MIXINS, so
# Plugin must be loaded before this file runs. The require is explicit on
# purpose - do not rely on the Dir.require_all alphabetical sweep in boot.rb.
require_relative './plugin'

module Lux
  module Plugin
    module Mount
      extend self

      Entry = Struct.new(:plugin, :src, :dst, :rel, :status, keyword_init: true)

      # status:
      #   :ok       - symlink points to this plugin's source and target exists
      #   :missing  - destination does not exist
      #   :stale    - symlink points to same plugin/same rel path but a different
      #               filesystem location (gem path drift) -> silent rewrite
      #   :broken   - symlink points to correct source but source vanished
      #   :local    - real file in the way, or symlink owned by another plugin,
      #               or symlink to an unrelated location -> leave alone

      # Color helpers. Callable as Output.dim(...) anywhere, or as private
      # instance methods (dim/yellow/green) where this module is included.
      module Output
        module_function

        def green(s)  = s.to_s.colorize(:green)
        def yellow(s) = s.to_s.colorize(:yellow)
        def dim(s)    = s.to_s.colorize(:light_black)
      end

      # Stateless file-system primitives. Both Descriptor and the top-level
      # Mount orchestrators depend on Linker - nothing here depends back on
      # Descriptor or on the orchestrators, so the dependency graph stays a
      # DAG (Mount -> Linker, Descriptor -> Linker).
      module Linker
        module_function

        def status_of plugin_name, src, dst, rel
          return :missing unless File.symlink?(dst) || dst.exist?
          # Real file in place: a byte-identical copy is one we manage
          # (:copied); anything else is a user file we leave alone (:local).
          return same_content?(src, dst) ? :copied : :local unless File.symlink?(dst)

          target = resolve_symlink(dst)
          expected = src.cleanpath

          if target == expected
            File.exist?(target) ? :ok : :broken
          elsif target.to_s =~ %r{/plugins/#{Regexp.escape(plugin_name)}/mount/#{Regexp.escape(rel.to_s)}\z}
            :stale
          else
            :local
          end
        end

        def ours? plugin_name, dst, rel
          return false unless File.symlink?(dst)
          target = resolve_symlink(dst)
          target.to_s =~ %r{/plugins/#{Regexp.escape(plugin_name)}/mount/#{Regexp.escape(rel.to_s)}\z}
        end

        def resolve_symlink dst
          raw = Pathname.new(File.readlink(dst))
          raw = dst.dirname.join(raw) unless raw.absolute?
          raw.cleanpath
        end

        def create_link entry
          FileUtils.mkdir_p(entry.dst.dirname)
          File.unlink(entry.dst) if File.symlink?(entry.dst) || entry.dst.exist?
          rel_src = entry.src.relative_path_from(entry.dst.dirname)
          File.symlink(rel_src, entry.dst)
          puts 'linked   %s -> %s %s' % [display(entry.dst).ljust(60), rel_src, Output.dim('(plugin: %s)' % entry.plugin)]
        end

        def warn_local entry
          puts 'local    %s %s' % [Output.yellow(display(entry.dst).ljust(60)), Output.dim('(plugin: %s)' % entry.plugin)]
        end

        # Copy the plugin source into the app as a real file (deploy mode).
        # preserve: true keeps the source mode, mirroring rsync --executability.
        def copy_file entry
          FileUtils.mkdir_p(entry.dst.dirname)
          File.unlink(entry.dst) if File.symlink?(entry.dst) || entry.dst.exist?
          FileUtils.cp(entry.src, entry.dst, preserve: true)
          puts 'copied   %s %s' % [display(entry.dst).ljust(60), Output.dim('(plugin: %s)' % entry.plugin)]
        end

        # Content equality ignoring trailing whitespace at the end of the file,
        # so a copy that differs only by a final newline still reads as same.
        def same_content? src, dst
          return false unless File.file?(dst)
          File.read(src.to_s).rstrip == File.read(dst.to_s).rstrip
        end

        def display path
          str = path.to_s.sub(Lux.root.to_s + '/', '')
          idx = str.rindex('plugins/')
          idx ? str[(idx + 'plugins/'.size)..] : str
        end
      end

      # Instance methods mixed into every plugin descriptor: the loaded
      # Lux::Hash returned by `Lux.plugin(:foo)` and the unloaded PluginRef
      # used by the CLI. Both expose `name` and `folder`.
      module Descriptor
        include Output

        # Yields [src_pathname, dst_pathname] for every leaf file under
        # <folder>/mount/. Returns an Enumerator if no block. Silent if no
        # mount/ folder.
        def mounts(&block)
          return enum_for(:mounts) unless block
          mount_root = Pathname.new(folder).join('mount')
          return unless mount_root.directory?
          mount_root.glob('**/*', File::FNM_DOTMATCH).reject { |p| p.directory? || %w[. ..].include?(p.basename.to_s) }.sort.each do |src|
            yield src, Lux.root.join(src.relative_path_from(mount_root))
          end
        end

        # Apply this plugin's mount/ entries. mode :symlink (default) drives
        # every entry toward a symlink - including reconverting :copied real
        # files back to links; mode :copy writes real-file copies instead.
        # Silent on healthy entries (:ok / :copied); warns on :local conflicts.
        # Returns Entry list.
        def mount! mode: :symlink
          mounts.map do |src, dst|
            rel = dst.relative_path_from(Lux.root)
            entry = Entry.new(plugin: name, src: src, dst: dst, rel: rel, status: Linker.status_of(name, src, dst, rel))
            if mode == :copy
              case entry.status
              when :copied then entry
              when :local  then Linker.warn_local(entry); entry
              else # :ok (symlink), :missing, :stale, :broken
                Linker.copy_file(entry)
                entry.status = :copied
                entry
              end
            else
              case entry.status
              when :ok then entry
              when :local then Linker.warn_local(entry); entry
              else # :missing, :stale, :broken, :copied -> (re)create symlink
                Linker.create_link(entry)
                entry.status = :linked
                entry
              end
            end
          end
        end

        # Unlink only this plugin's owned symlinks. Returns removed dst paths.
        def unmount!
          removed = []
          mounts do |_src, dst|
            rel = dst.relative_path_from(Lux.root)
            next unless File.symlink?(dst) && Linker.ours?(name, dst, rel)
            File.unlink(dst)
            puts 'unlinked %s %s' % [yellow(Linker.display(dst).ljust(60)), dim('(plugin: %s)' % name)]
            removed << dst
          end
          removed
        end
      end

      PluginRef = Struct.new(:name, :folder) do
        include Descriptor
      end

      # Register Descriptor with the plugin loader so loaded descriptors gain
      # .mounts / .mount! / .unmount! the same way PluginRef does.
      Lux::Plugin::DESCRIPTOR_MIXINS << Descriptor unless Lux::Plugin::DESCRIPTOR_MIXINS.include?(Descriptor)

      # === CLI orchestrators ==================================================

      def apply plugin_name = nil, mode: :symlink, git_rm: false
        pruned  = prune_orphans plugin_name
        results = plugin_refs(plugin_name).flat_map { |p| p.mount!(mode: mode) }
        if mode == :symlink
          write_git_exclude
          git_untrack results if git_rm
        end
        report_summary results, pruned
        results
      end

      # Pass 1: unlink every plugin-owned symlink (delegated to each ref).
      # Pass 2 (only when called without a plugin name): walk Lux.root and
      # list every remaining symlink that isn't from a plugin mount/.
      def unlink plugin_name = nil
        removed = plugin_refs(plugin_name).flat_map(&:unmount!)
        puts Output.dim('unlinked=%d' % removed.size)

        return removed if plugin_name

        user_links = scan_user_symlinks
        return removed if user_links.empty?

        puts ''
        puts Output.dim('user-added symlinks (not from any plugin mount):')
        user_links.each { |path, target| puts '  %s -> %s' % [Linker.display(path), target] }
        removed
      end

      def list plugin_name = nil
        plugin_refs(plugin_name).flat_map do |plugin|
          plugin.mounts.map do |src, dst|
            rel = dst.relative_path_from(Lux.root)
            Entry.new(plugin: plugin.name, src: src, dst: dst, rel: rel, status: Linker.status_of(plugin.name, src, dst, rel))
          end
        end
      end

      def print_list plugin_name = nil
        entries = list(plugin_name)
        if entries.empty?
          puts 'No plugin mounts found'
          return entries
        end

        entries.group_by(&:plugin).sort.each do |plugin, group|
          puts plugin.to_s.colorize(:blue)
          group.sort_by { |e| e.dst.to_s }.each do |e|
            puts '  %-9s %s' % [e.status, e.dst.to_s.sub(Lux.root.to_s + '/', '')]
          end
        end
        entries
      end

      def doctor fix: false
        entries = list
        if entries.empty?
          puts 'No plugin mounts found'
          return entries
        end

        entries.each { |e| puts format_entry(e) }

        unhealthy = entries.reject { |e| %i[ok copied].include?(e.status) }

        if unhealthy.empty?
          puts '%s healthy mount(s)' % Output.green(entries.size.to_s)
        elsif fix
          puts '--fix: applying %d entr(ies)' % unhealthy.size
          apply
        end

        entries
      end

      SCAN_SKIP_DIRS ||= %w[node_modules dist build tmp .next .git coverage].freeze

      # Markers around the managed region in .git/info/exclude. The block is
      # rebuilt on every `lux mount` (symlink mode); anything outside it is kept.
      GIT_EXCLUDE_HEADER ||= '# lux mount - exclude symlinks'
      GIT_EXCLUDE_FOOTER ||= '# lux mount - end'

      # Walks Lux.root and returns [[path, raw_target], ...] for every symlink
      # whose target is NOT inside any plugins/<name>/mount/ tree. Skips the
      # SCAN_SKIP_DIRS subtrees. Public for reuse from external tooling.
      def scan_user_symlinks
        root = Lux.root.to_s
        result = []
        Find.find(root) do |path|
          if File.symlink?(path)
            target = Linker.resolve_symlink(Pathname.new(path)).to_s
            result << [path, File.readlink(path)] unless target =~ %r{/plugins/[^/]+/mount/}
            next
          end
          Find.prune if File.directory?(path) && path != root && SCAN_SKIP_DIRS.include?(File.basename(path))
        end
        result
      end

      # Walks Lux.root and removes broken symlinks that point into a
      # plugins/<name>/mount/ tree whose source file no longer exists (the
      # plugin dropped the file). Restricted to `plugin_name` when given.
      # These orphans are invisible to mount! because it only iterates the
      # sources that still exist. Returns removed dst paths.
      def prune_orphans plugin_name = nil
        owner = plugin_name ? Regexp.escape(plugin_name.to_s) : '[^/]+'
        filter = %r{/plugins/(#{owner})/mount/}
        removed = []
        Find.find(Lux.root.to_s) do |path|
          if File.symlink?(path)
            target = Linker.resolve_symlink(Pathname.new(path)).to_s
            if (m = filter.match(target)) && !File.exist?(target)
              File.unlink(path)
              puts 'removed  %s %s' % [Output.yellow(Linker.display(Pathname.new(path)).ljust(60)), Output.dim('(dead link, plugin: %s)' % m[1])]
              removed << path
            end
            next
          end
          Find.prune if File.directory?(path) && path != Lux.root.to_s && SCAN_SKIP_DIRS.include?(File.basename(path))
        end
        prune_empty_dirs removed.map { |p| File.dirname(p) }
        removed
      end

      private

      # Remove the directory shells left behind after pruning links. mount!
      # materializes parent dirs as real folders via mkdir_p, so a plugin that
      # drops every file under a subtree leaves empty dirs. Walk upward from
      # each parent until a non-empty dir or Lux.root. Deepest-first so a child
      # is cleared before its parent is tested. Dir.rmdir only removes empty
      # dirs, so dirs holding real files (or a stray .DS_Store) are left alone.
      def prune_empty_dirs dirs
        root = Lux.root.to_s
        dirs.uniq.sort_by { |d| -d.length }.each do |dir|
          while dir.start_with?(root) && dir != root && Dir.exist?(dir) && (Dir.entries(dir) - %w[. ..]).empty?
            Dir.rmdir(dir)
            puts 'rmdir    %s' % Output.dim(Linker.display(Pathname.new(dir)))
            dir = File.dirname(dir)
          end
        end
      end

      # Rebuild the managed block in .git/info/exclude so the machine-specific
      # plugin symlinks (their targets embed the ruby version + gem hash) never
      # surface as repo changes. Lists every plugin mount symlink regardless of
      # which plugin `apply` was scoped to, preserves any other content in the
      # file, and is a no-op outside a git working tree.
      def write_git_exclude
        exclude = git_info_exclude_path or return

        links = list.select { |e| %i[ok linked].include?(e.status) }
                    .map { |e| '/' + e.dst.relative_path_from(Lux.root).to_s }
                    .uniq.sort

        kept = exclude.exist? ? strip_managed_block(exclude.read.lines.map(&:chomp)) : []
        kept.pop while kept.last == ''

        unless links.empty?
          kept << '' unless kept.empty?
          kept.concat [GIT_EXCLUDE_HEADER, *links, GIT_EXCLUDE_FOOTER]
        end

        exclude.dirname.mkpath
        exclude.write(kept.empty? ? '' : kept.join("\n") + "\n")
        puts Output.dim('excluded %d symlinked file(s) in .git/info/exclude' % links.size) unless links.empty?
      end

      # Drop the HEADER..FOOTER region (inclusive) so the block can be rebuilt
      # idempotently; a header with no footer (legacy/truncated) drops to EOF.
      def strip_managed_block lines
        out, skip = [], false
        lines.each do |line|
          if line == GIT_EXCLUDE_HEADER then skip = true; next end
          if skip
            skip = false if line == GIT_EXCLUDE_FOOTER
            next
          end
          out << line
        end
        out
      end

      # Path to <git-dir>/info/exclude for Lux.root, following a `.git` *file*
      # (worktrees/submodules use "gitdir: <path>"). nil when not a git repo.
      def git_info_exclude_path
        dot_git = Lux.root.join('.git')
        git_dir =
          if dot_git.directory?
            dot_git
          elsif dot_git.file? && (ref = dot_git.read[/^gitdir:\s*(.+)$/, 1])
            ref = Pathname.new(ref.strip)
            ref.absolute? ? ref : Lux.root.join(ref).cleanpath
          end
        git_dir&.directory? ? git_dir.join('info', 'exclude') : nil
      end

      # Untrack the plugin mount symlinks (git rm --cached) so the exclude block
      # can take over - files stay on disk and are recreated by mount. Opt-in via
      # `lux mount --git-rm`: a one-time cleanup, idempotent, no-op outside a git
      # repo. Only symlink entries (never :local real files). Does not commit.
      def git_untrack results
        return unless git_info_exclude_path
        root = Lux.root.to_s
        candidates = results.select { |e| %i[ok linked].include?(e.status) }
                            .map { |e| e.dst.relative_path_from(Lux.root).to_s }
        return if candidates.empty?
        tracked = IO.popen(['git', '-C', root, 'ls-files', '-z', '--', *candidates], &:read).split("\x0")
        return puts(Output.dim('git rm: no tracked mount symlinks')) if tracked.empty?
        system('git', '-C', root, 'rm', '--cached', '--quiet', '--', *tracked)
        puts Output.dim('git rm --cached: untracked %d mount symlink(s); commit to finalize' % tracked.size)
      end

      def plugin_refs plugin_name
        names = plugin_name ? [plugin_name.to_s] : Lux::Plugin.normalize_names(Lux.config[:plugins])
        names.map { |name| resolve_plugin(name) }
      end

      # Resolve a plugin name to a PluginRef using the same lookup as Lux.plugin
      # (Lux.root/plugins/<name>, then Lux.fw_root/plugins/<name>) without loading.
      def resolve_plugin name
        name = name.to_s
        folder = [Lux.root, Lux.fw_root].map { |r| Pathname.new(r).join('plugins', name) }.find(&:directory?)
        die(%{Plugin "#{name}" not found}) unless folder
        PluginRef.new(name, folder.to_s)
      end

      def format_entry e
        color = %i[ok copied].include?(e.status) ? :green : :yellow
        '  %-9s %-12s %s' % [e.status.to_s.colorize(color), e.plugin, Linker.display(e.dst)]
      end

      # Per-status change line prints only when something actually changed
      # (linked/local/removed) - mount stays quiet when every entry is already
      # healthy (:ok / :copied). The bottom info line always reports how many
      # files are linked vs copied from plugins. copy_file/create_link already
      # print one line per change, so steady states stay silent.
      def report_summary results, pruned = []
        steady  = %i[ok copied]
        changed = results.reject { |e| steady.include?(e.status) }
        unless changed.empty? && pruned.empty?
          by_status = changed.group_by(&:status).transform_values(&:size)
          by_status[:removed] = pruned.size if pruned.any?
          puts Output.dim(by_status.map { |k, v| '%s=%d' % [k, v] }.join(' '))
        end
        return if results.empty?
        linked  = results.count { |e| %i[ok linked].include?(e.status) }
        copied  = results.count { |e| e.status == :copied }
        plugins = results.map(&:plugin).uniq.size
        parts = []
        parts << '%d linked' % linked if linked > 0
        parts << '%d copied' % copied if copied > 0
        parts = ['0 linked'] if parts.empty?
        puts Output.dim('%s from %d plugin%s' % [parts.join(', '), plugins, ('s' if plugins != 1)])
      end
    end
  end
end
