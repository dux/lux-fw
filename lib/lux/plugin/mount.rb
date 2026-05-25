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
          return :local unless File.symlink?(dst)

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

        # Apply this plugin's mount/ entries. Silent on :ok; creates missing/
        # stale/broken links; warns on :local conflicts. Returns Entry list.
        def mount!
          mounts.map do |src, dst|
            rel = dst.relative_path_from(Lux.root)
            entry = Entry.new(plugin: name, src: src, dst: dst, rel: rel, status: Linker.status_of(name, src, dst, rel))
            case entry.status
            when :ok then entry
            when :missing, :stale, :broken
              Linker.create_link(entry)
              entry.status = :linked
              entry
            when :local
              Linker.warn_local(entry)
              entry
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

      def apply plugin_name = nil
        results = plugin_refs(plugin_name).flat_map(&:mount!)
        report_summary results
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

        unhealthy = entries.reject { |e| e.status == :ok }

        if unhealthy.empty?
          puts '%s healthy mount(s)' % Output.green(entries.size.to_s)
        elsif fix
          puts '--fix: applying %d entr(ies)' % unhealthy.size
          apply
        end

        entries
      end

      SCAN_SKIP_DIRS ||= %w[node_modules dist build tmp .next .git coverage].freeze

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

      private

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
        color = e.status == :ok ? :green : :yellow
        '  %-9s %-12s %s' % [e.status.to_s.colorize(color), e.plugin, Linker.display(e.dst)]
      end

      def report_summary results
        return if results.empty?
        by_status = results.group_by(&:status).transform_values(&:size)
        puts Output.dim(by_status.map { |k, v| '%s=%d' % [k, v] }.join(' '))
      end
    end
  end
end
