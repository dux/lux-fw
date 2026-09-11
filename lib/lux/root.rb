require 'pathname'
require 'find'

module Lux
  # Ordered overlay of app roots. The app root comes first, then every loaded
  # plugin's `mount/` root is appended. Resolution walks the list and the first
  # hit wins, so an app file shadows a plugin file with no special casing.
  #
  #   Lux.root.path 'app/views/main/root.haml'   # first existing, else raise
  #   Lux.root.file 'rollup.config.js'           # same, asserting a file
  #   Lux.root.lib  'my_lib'                     # resolve + require a ruby lib
  #   Lux.root.files 'app/**/*.rb'               # merged, first root shadows
  #
  # Writes and unresolved paths still land under the real app root; only reads
  # consult the overlay.
  class Root < Pathname
    NotFound ||= Class.new(StandardError)
    NONE ||= Object.new.freeze

    class << self
      def overlays
        @overlays ||= []
      end

      def add path
        path = Pathname.new(path).cleanpath
        overlays << path unless overlays.include?(path)
        path
      end

      def roots
        [Lux.root, *overlays]
      end

      # Silent primitive: first existing path across roots, nil when missing.
      # An absolute argument is checked as-is.
      def resolve rel
        rel = Pathname.new(rel)
        return rel if rel.absolute?

        roots.each do |root|
          candidate = root.join(rel)
          return candidate if candidate.exist?
        end
        nil
      end

      # Finder: any existing path, raises listing every location tried.
      def path rel
        resolve(rel) || not_found(rel)
      end

      # Finder: same as path, but asserts a regular file.
      def file rel
        found = path(rel)
        return found if found.file?
        not_found(rel, 'is not a file')
      end

      # Loader: resolve a ruby lib and require it. `.rb` is appended when the
      # name carries no extension.
      def lib rel
        found = file(rel.to_s.end_with?('.rb') ? rel : "#{rel}.rb")
        require found.to_s
        found
      end

      # Merged enumeration. Files sharing a relative path collapse to the first
      # root; the result is sorted shallowest-first so require order is stable.
      def files glob
        merged(glob).select(&:file?).sort_by { |f| [f.to_s.count('/'), f.to_s] }
      end

      # Merged directory listing under `rel`, first root shadows by name.
      def dirs rel
        seen = {}
        roots.each do |root|
          dir = root.join(rel)
          next unless dir.directory?
          Dir.children(dir).sort.each do |name|
            next if seen.key?(name)
            child = dir.join(name)
            seen[name] = child if child.directory?
          end
        end
        seen.values
      end

      private

      def merged glob
        seen = {}
        roots.each do |root|
          base = Pathname.new(root)
          base.glob(glob).sort.each do |abs|
            seen[abs.relative_path_from(base).to_s] ||= abs
          end
        end
        seen.values
      end

      def not_found rel, note = nil
        tried = roots.map { '  %s' % _1.join(rel) }.join("\n")
        raise NotFound, 'Lux.root cannot find %p%s.%sLooked in:%s%s' % [rel, note ? " (#{note})" : '', $/, $/, tried]
      end
    end

    # Instance API - `Lux.root.path(...)` mirrors the class methods.
    #
    # Pathname's builtin uses an internal `path` accessor with no argument, so a
    # bare call falls through to super and only an argument selects the finder.
    def path(rel = NONE)
      return super() if rel.equal?(NONE)
      self.class.path(rel)
    end

    def file(rel)    = self.class.file(rel)
    def lib(rel)     = self.class.lib(rel)
    def files(glob)  = self.class.files(glob)
    def dirs(rel)    = self.class.dirs(rel)
    def resolve(rel) = self.class.resolve(rel)

    # Strip whichever app root a path lives under, for logs and debug links.
    # Absolute paths that live under no root are returned unchanged.
    def pretty(path)
      str = path.to_s
      self.class.roots.each do |root|
        base = Pathname.new(root).to_s
        return '.' + str[base.size..] if str == base || str.start_with?(base + '/')
      end
      str
    end

    # Map a path under any root to the matching path under the writable app
    # root. Generated output (auto-*.tmp.*) must land in the app tree even when
    # its source ships in a plugin mount.
    def mirror(path)
      path = Pathname.new(path)
      self.class.roots.each do |root|
        base = Pathname.new(root)
        next unless path.to_s == base.to_s || path.to_s.start_with?(base.to_s + '/')
        return join(path.relative_path_from(base))
      end
      path
    end

    # Resolve a top-level app constant on demand: `ApplicationModel` ->
    # app/**/application_model.rb across every root. Used by Object.const_missing
    # so plugins can reference app base classes during boot, before config/app.rb
    # eager-loads ./app. Returns true once the file is required.
    def autoload_const(name)
      target = name.to_s.underscore
      file = self.class.files('app/**/*.rb').find { |f| File.basename(f.to_s, '.rb') == target }
      return false unless file

      require file.to_s
      true
    end

    # Require every *.rb under `rel` across all roots, deduped by relative path.
    # Mirrors Dir.require_all: skips specs and view templates.
    def require_all rel = 'app', opts = {}
      self.class.files('%s/**/*.rb' % rel)
        .reject { |f| f.to_s.include?('_spec.rb') || f.to_s.include?('/app/views/') }
        .select { |f| opts[:skip] ? !f.to_s.include?(opts[:skip]) : true }
        .each { |f| require f.to_s }
      self
    end
  end
end
