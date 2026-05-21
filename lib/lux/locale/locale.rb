# Lux::Locale - small, namespaced translation lookup.
#
#   Lux.locale.default   = :en
#   Lux.locale.available = %i[en de hr]
#
#   Lux.locale.t('users.welcome', name: 'Joe')
#   Lux.locale.set('users.welcome', 'Hi %{name}', locale: :en)
#
# Every key is namespaced - the first dotted segment is the namespace, the
# rest is the subkey stored inside the flat text file at
# `./config/locales/<namespace>.<locale>.txt`. Single-segment keys raise.
#
# File format - one entry per line, `key: value`:
#
#   profile.title: Profile
#   welcome: Hi %{name}
#
# Keys never contain spaces or colons. Lines are sorted alphabetically by
# key on every write. Blank lines and lines without `:` are skipped on
# read.
#
# Two extension points:
#   * `namespace(:foo) { |subkey, locale| ... }` - per-namespace dynamic
#     handler. Non-nil return wins; nil falls through to the file.
#   * `before_get` / `before_set` - global pre-hooks. before_get short-
#     circuits the lookup when it returns non-nil; before_set's return
#     value replaces the value being stored (nil = passthrough).
#
# In dev the file cache invalidates on mtime change - no reloader wiring
# required.

module Lux
  module Locale
    extend self

    class Unknown < StandardError; end

    # --- registry --------------------------------------------------------

    attr_writer :default, :available, :dir

    def default
      @default ||= :en
    end

    def available
      @available ||= [default]
    end

    # Directory containing `<namespace>.<locale>.txt` files.
    def dir
      @dir ||= Pathname.new('./config/locales')
    end

    # --- per-request current locale --------------------------------------

    # Pulls from Lux.current.locale (typically set by Nav from the URL
    # prefix) and validates against `available`. Falls back to `default`
    # when unset.
    def current
      lc = (Lux.current.locale.presence || default).to_sym
      unless available.map(&:to_sym).include?(lc)
        raise Unknown, "locale #{lc.inspect} not in #{available.inspect}"
      end
      lc
    end

    # --- hooks -----------------------------------------------------------

    # Lux.locale.before_get { |locale, key| ... }
    # Return non-nil to short-circuit the lookup with that value.
    def before_get(&block)
      @before_get = block
    end

    # Lux.locale.before_set { |locale, key, value| ... }
    # Return non-nil to replace the value being written (e.g. normalize,
    # validate). nil leaves the original value untouched.
    def before_set(&block)
      @before_set = block
    end

    # Lux.locale.namespace(:product) { |subkey, locale| ... }
    # Dynamic backend for one namespace. Non-nil wins; nil falls through
    # to the file for that namespace.
    def namespace(name, &block)
      (@namespaces ||= {})[name.to_sym] = block
    end

    # --- public API ------------------------------------------------------

    def t(key, locale: nil, fallback: nil, **vars)
      key = key.to_s
      raise ArgumentError, 'blank key' if key.empty?
      ns, subkey = split_key(key)
      lc = (locale || current).to_sym

      val = nil
      val = @before_get.call(lc, key) if @before_get
      val ||= resolve(ns, subkey, lc)
      val ||= resolve(ns, subkey, default) if lc != default
      val ||= fallback

      return "[#{key}]" if val.nil?

      vars.empty? ? val : (val.to_s % vars rescue val)
    end

    def set(key, value, locale: nil)
      key = key.to_s
      raise ArgumentError, 'blank key' if key.empty?
      ns, subkey = split_key(key)
      lc = (locale || current).to_sym

      if @before_set
        replaced = @before_set.call(lc, key, value)
        value = replaced unless replaced.nil?
      end

      file_set(ns, lc, subkey, value)
      value
    end

    # Drop file cache. Not normally needed - mtime check handles dev
    # edits - but useful in tests and after bulk file rewrites.
    def reload!
      @cache = {}
      nil
    end

    # --- internal --------------------------------------------------------

    private

    # Per-locale resolution chain inside a single namespace:
    # registered handler first, then the flat-file lookup.
    def resolve(ns, subkey, lc)
      if @namespaces && (handler = @namespaces[ns])
        out = handler.call(subkey, lc)
        return out unless out.nil?
      end
      file_get(ns, lc, subkey)
    end

    def split_key(key)
      ns, *rest = key.split('.')
      if rest.empty?
        raise ArgumentError,
          "key #{key.inspect} must be namespaced (e.g. 'users.welcome')"
      end
      [ns.to_sym, rest.join('.')]
    end

    def file_path(ns, lc)
      dir.join("#{ns}.#{lc}.txt")
    end

    def cache
      @cache ||= {}
    end

    # Returns the {subkey => value} table for a (ns, locale), or nil if
    # the file doesn't exist. Re-reads transparently when mtime changes.
    def load_file(ns, lc)
      path = file_path(ns, lc)
      return nil unless path.exist?

      key    = [ns, lc]
      mtime  = File.mtime(path)
      cached = cache[key]
      return cached[:data] if cached && cached[:mtime] == mtime

      data = parse(path.read)
      cache[key] = { data: data, mtime: mtime }
      data
    end

    def file_get(ns, lc, subkey)
      table = load_file(ns, lc)
      table && table[subkey]
    end

    # Load -> merge subkey -> sort -> atomic rewrite -> drop cache row.
    def file_set(ns, lc, subkey, value)
      path = file_path(ns, lc)
      dir.mkpath unless dir.exist?

      table = path.exist? ? parse(path.read) : {}
      table[subkey] = value.to_s

      tmp = "#{path}.tmp"
      File.write(tmp, serialize(table))
      File.rename(tmp, path)

      cache.delete([ns, lc])
      value
    end

    # 'foo.bar: hello world' -> { 'foo.bar' => 'hello world' }.
    # Blank lines and lines without ':' are skipped.
    def parse(text)
      out = {}
      text.each_line do |line|
        line = line.chomp
        next if line.strip.empty?
        key, sep, value = line.partition(':')
        next if sep.empty?
        out[key.strip] = value.sub(/\A /, '')   # drop the conventional single space
      end
      out
    end

    def serialize(table)
      table.keys.sort.map { |k| "#{k}: #{table[k]}\n" }.join
    end
  end
end
