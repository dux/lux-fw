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
      #   :conflict - real file in the way, or symlink owned by another plugin,
      #               or symlink to an unrelated location -> skip + warn

      def apply plugin_name = nil
        results = list(plugin_name).map do |e|
          case e.status
          when :ok       then e
          when :missing, :stale, :broken
            create_link(e)
            e.status = :linked
            e
          when :conflict then warn_conflict(e); e
          end
        end

        report_summary results
        results
      end

      def list plugin_name = nil
        sources(plugin_name).flat_map do |plugin, mount_root|
          mount_root.glob('**/*').reject(&:directory?).sort.map do |src|
            rel = src.relative_path_from(mount_root)
            dst = Lux.root.join(rel)
            Entry.new(plugin: plugin.name, src: src, dst: dst, rel: rel, status: status_of(plugin, src, dst, rel))
          end
        end
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
          puts '%s healthy mount(s)' % entries.size.to_s.colorize(:green)
        elsif fix
          puts '--fix: applying %d entr(ies)' % unhealthy.size
          apply
        end

        entries
      end

      def remove plugin_name
        plugin = Lux::Plugin.get(plugin_name)
        mount_root = Pathname.new(plugin.folder).join('mount')
        return puts("Plugin #{plugin_name} has no mount/ folder") unless mount_root.directory?

        removed = 0
        mount_root.glob('**/*').reject(&:directory?).each do |src|
          rel = src.relative_path_from(mount_root)
          dst = Lux.root.join(rel)
          next unless File.symlink?(dst) && ours?(plugin, dst, rel)

          File.unlink(dst)
          puts 'unlinked %s' % display(dst)
          removed += 1
        end

        puts 'Removed %d link(s) for %s' % [removed, plugin_name]
      end

      private

      def sources plugin_name
        plugins = plugin_name ? [Lux::Plugin.get(plugin_name)] : Lux::Plugin.loaded
        plugins.map do |p|
          root = Pathname.new(p.folder).join('mount')
          [p, root] if root.directory?
        end.compact
      end

      def status_of plugin, src, dst, rel
        return :missing unless File.symlink?(dst) || dst.exist?
        return :conflict unless File.symlink?(dst)

        target = resolve_symlink(dst)
        expected = src.cleanpath

        if target == expected
          File.exist?(target) ? :ok : :broken
        elsif target.to_s =~ %r{/plugins/#{Regexp.escape(plugin.name)}/mount/#{Regexp.escape(rel.to_s)}\z}
          :stale
        else
          :conflict
        end
      end

      def ours? plugin, dst, rel
        return false unless File.symlink?(dst)
        target = resolve_symlink(dst)
        target.to_s =~ %r{/plugins/#{Regexp.escape(plugin.name)}/mount/#{Regexp.escape(rel.to_s)}\z}
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
        puts 'linked   %s -> %s' % [display(entry.dst), rel_src]
      end

      def warn_conflict entry
        puts 'skipped  %s (conflict; owned by foreign file or different plugin)' % display(entry.dst).colorize(:yellow)
      end

      def format_entry e
        color =
          case e.status
          when :ok then :green
          when :conflict then :red
          else :yellow
          end
        '  %-9s %-12s %s' % [e.status.to_s.colorize(color), e.plugin, display(e.dst)]
      end

      def report_summary results
        by_status = results.group_by(&:status).transform_values(&:size)
        return if results.empty?
        puts by_status.map { |k, v| '%s=%d' % [k, v] }.join(' ')
      end

      def display path
        path.to_s.sub(Lux.root.to_s + '/', '')
      end
    end
  end
end
