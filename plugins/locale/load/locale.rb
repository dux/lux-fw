# Lux::Locale - small, namespaced translation lookup.
#
#   Lux.locale.default   = :en
#   Lux.locale.available = %i[en de hr]
#
#   Lux.locale.t('users.welcome', name: 'Joe')
#   Lux.locale.set('users.welcome', 'Hi %{name}', locale: :en)
#   Lux.locale.t                                  # current (or default) locale
#
# Every key is namespaced - the first dotted segment is the namespace, the
# rest is the subkey stored inside the flat text file at
# `./config/locales/<namespace>/<locale>.txt`. Single-segment keys raise.
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
# Large texts (terms, legal pages, long emails) live as standalone files
# rather than flat-file lines. Two whole-file forms, both raw (no
# rendering) and sharing the default-locale fallback, `[key]` marker and
# `%{var}` interpolation of the line lookup:
#
#   * `t('<ext>:<dotted.path>')` - prefix is the file extension, the path's
#     leading segments are folders and the last is the filename, rooted at
#     `dir/<ext>`:
#
#       t('md:legal.terms') -> ./config/locales/md/legal/terms.<locale>.md
#
#   * `t('/views/relative/path.ext')` - rooted at the views dir, the locale
#     is inserted before the final extension. For localized content kept
#     alongside templates:
#
#       t('/main/legal/policy.html') -> app/views/main/legal/policy.<locale>.html
#
# `language:` is accepted as an alias for the `locale:` keyword.
#
# In dev the file cache invalidates on mtime change - no reloader wiring
# required.

module Lux
  module Locale
    extend self

    class Unknown < StandardError; end

    # Common languages keyed by code. `name` in the language itself, `eng`
    # the English name, `locale` the ISO-3166 country code used for the flag
    # (flags are per country, not per language). Handy for a locale switcher:
    #   Lux.locale.available.map { |l| LANGUAGES[l.to_s] }
    LANGUAGES ||= {
      'en' => { name: 'English',          eng: 'English',    locale: 'gb' },
      'hr' => { name: 'Hrvatski',         eng: 'Croatian',   locale: 'hr' },
      'de' => { name: 'Deutsch',          eng: 'German',     locale: 'de' },
      'fr' => { name: 'Français',         eng: 'French',     locale: 'fr' },
      'es' => { name: 'Español',          eng: 'Spanish',    locale: 'es' },
      'it' => { name: 'Italiano',         eng: 'Italian',    locale: 'it' },
      'pt' => { name: 'Português',        eng: 'Portuguese', locale: 'pt' },
      'nl' => { name: 'Nederlands',       eng: 'Dutch',      locale: 'nl' },
      'sv' => { name: 'Svenska',          eng: 'Swedish',    locale: 'se' },
      'no' => { name: 'Norsk',            eng: 'Norwegian',  locale: 'no' },
      'da' => { name: 'Dansk',            eng: 'Danish',     locale: 'dk' },
      'fi' => { name: 'Suomi',            eng: 'Finnish',    locale: 'fi' },
      'is' => { name: 'Íslenska',         eng: 'Icelandic',  locale: 'is' },
      'pl' => { name: 'Polski',           eng: 'Polish',     locale: 'pl' },
      'cs' => { name: 'Čeština',          eng: 'Czech',      locale: 'cz' },
      'sk' => { name: 'Slovenčina',       eng: 'Slovak',     locale: 'sk' },
      'sl' => { name: 'Slovenščina',      eng: 'Slovenian',  locale: 'si' },
      'sr' => { name: 'Српски',           eng: 'Serbian',    locale: 'rs' },
      'bs' => { name: 'Bosanski',         eng: 'Bosnian',    locale: 'ba' },
      'mk' => { name: 'Македонски',       eng: 'Macedonian', locale: 'mk' },
      'bg' => { name: 'Български',         eng: 'Bulgarian',  locale: 'bg' },
      'ro' => { name: 'Română',           eng: 'Romanian',   locale: 'ro' },
      'hu' => { name: 'Magyar',           eng: 'Hungarian',  locale: 'hu' },
      'uk' => { name: 'Українська',       eng: 'Ukrainian',  locale: 'ua' },
      'ru' => { name: 'Русский',          eng: 'Russian',    locale: 'ru' },
      'el' => { name: 'Ελληνικά',         eng: 'Greek',      locale: 'gr' },
      'tr' => { name: 'Türkçe',           eng: 'Turkish',    locale: 'tr' },
      'et' => { name: 'Eesti',            eng: 'Estonian',   locale: 'ee' },
      'lv' => { name: 'Latviešu',         eng: 'Latvian',    locale: 'lv' },
      'lt' => { name: 'Lietuvių',         eng: 'Lithuanian', locale: 'lt' },
      'ca' => { name: 'Català',           eng: 'Catalan',    locale: 'es' },
      'eu' => { name: 'Euskara',          eng: 'Basque',     locale: 'es' },
      'gl' => { name: 'Galego',           eng: 'Galician',   locale: 'es' },
      'ga' => { name: 'Gaeilge',          eng: 'Irish',      locale: 'ie' },
      'ja' => { name: '日本語',            eng: 'Japanese',   locale: 'jp' },
      'zh' => { name: '中文',              eng: 'Chinese',    locale: 'cn' },
      'ko' => { name: '한국어',            eng: 'Korean',     locale: 'kr' },
      'hi' => { name: 'हिन्दी',             eng: 'Hindi',      locale: 'in' },
      'th' => { name: 'ไทย',              eng: 'Thai',       locale: 'th' },
      'vi' => { name: 'Tiếng Việt',       eng: 'Vietnamese', locale: 'vn' },
      'id' => { name: 'Bahasa Indonesia', eng: 'Indonesian', locale: 'id' },
      'ms' => { name: 'Bahasa Melayu',    eng: 'Malay',      locale: 'my' },
      'ar' => { name: 'العربية',          eng: 'Arabic',     locale: 'sa' },
      'he' => { name: 'עברית',            eng: 'Hebrew',     locale: 'il' },
      'fa' => { name: 'فارسی',            eng: 'Persian',    locale: 'ir' }
    }.freeze

    # --- registry --------------------------------------------------------

    attr_writer :default, :available, :dir, :store
    attr_reader :store

    def default
      @default ||= :en
    end

    def available
      @available ||= [default]
    end

    # Directory containing `<namespace>/<locale>.txt` files.
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

    # True when the active `localized` scope was declared force: true - the
    # prefix is then required, including for the default locale.
    def force?
      !!Lux.current[:locale_force]
    end

    # Locale-prefixed path. Accepts a String ("/foo") or an object that knows
    # its own path (object.path, else object.to_path); anything else falls back
    # to to_s. The default locale stays bare unless the request is forced; every
    # other locale carries the /xx prefix. Reachable as lux.lpath from a request
    # and as the lpath template helper.
    #
    #   Lux.locale.path('/service')              # "/service" (default) or "/hr/service"
    #   Lux.locale.path('/service', locale: :hr) # "/hr/service"
    #   Lux.locale.path('/')                     # "/" or "/hr"
    #   Lux.locale.path(user)                    # user.path, locale-prefixed
    #
    # `prefix: true` emits the prefix for the default locale too, so a switcher
    # can record an explicit return to it; the `localized` scope canonicalizes
    # /en/service back to the bare /service.
    def path value = '/', locale: nil, prefix: false
      value  = localized_path(value)
      value  = '/' if value.to_s.empty?
      locale = (locale || current).to_s

      if locale == default.to_s && !force? && !prefix
        value
      elsif value == '/'
        "/#{locale}"
      else
        "/#{locale}#{value}"
      end
    end

    # SEO link attributes for a locale-free path: a self-canonical for the
    # current locale, an alternate per available locale, and x-default for the
    # default locale. `base` is the absolute origin (trailing slash ignored).
    # Returns an array of attribute hashes a view renders as-is:
    #
    #   - Lux.locale.seo_links('/docs', base: 'https://example.com').each do |link|
    #     %link{ link }
    def seo_links value = '/', base: ''
      base = base.to_s.sub(%r{/+\z}, '')

      links = [{ rel: 'canonical', href: "#{base}#{path(value, locale: current)}" }]

      available.each do |loc|
        links << { rel: 'alternate', hreflang: loc.to_s, href: "#{base}#{path(value, locale: loc)}" }
      end

      links << { rel: 'alternate', hreflang: 'x-default', href: "#{base}#{path(value, locale: default)}" }
      links
    end

    # Locale for an IP-geo country code, so a first-time visitor can be sent to
    # the right /xx page. Reads CF-IPCountry (Cloudflare), then X-Geo-Country /
    # X-Country for other proxies; pass `country` to map one directly. Countries
    # are matched through LANGUAGES' country field, so only an available locale
    # wins and unknown codes (XX, T1) return nil.
    #
    #   Lux.locale.geo_locale('DE')  # :de
    #   Lux.locale.geo_locale('US')  # nil (en maps to gb; default stays bare)
    def geo_locale country = nil
      request = Lux.current.request
      country ||= request.get_header('HTTP_CF_IPCOUNTRY') ||
                  request.get_header('HTTP_X_GEO_COUNTRY') ||
                  request.get_header('HTTP_X_COUNTRY')

      code = country.to_s.downcase
      return nil if code.empty?

      loc = available.map(&:to_s).find { |lc| (LANGUAGES.dig(lc, :locale) || lc) == code }
      loc&.to_sym
    end

    private

    def localized_path value
      return value if value.is_a?(::String)
      return value.path    if value.respond_to?(:path)
      return value.to_path if value.respond_to?(:to_path)
      value.to_s
    end

    public

    # Resolve the locale for a web request and remember it across pages
    # that carry no URL prefix ("silent" translated pages).
    #
    # Precedence:
    #   1. /XX URL prefix     - explicit choice, peeled off nav.path by
    #                           Nav#locale, and stored in the session
    #   2. session[:locale]   - last explicitly used locale
    #   3. default
    #
    # Sets and returns Lux.current.locale (string). Writes the session only
    # on an explicit URL choice, so a plain visitor gets no needless cookie.
    def detect
      allowed = available.map(&:to_s)
      session = Lux.current.session

      # Nav#locale peels /XX off the path only when the block returns truthy
      url_locale = Lux.current.nav.locale { |seg| seg.to_s.downcase if allowed.include?(seg.to_s.downcase) }

      locale = (url_locale || session[:locale]).to_s
      locale = default.to_s unless allowed.include?(locale)   # guard nil / stale session value

      session[:locale]   = locale if url_locale && session[:locale] != locale  # remember last explicit choice
      Lux.current.locale = locale
    end

    # Flag image URL for a language code, served from flagcdn.com. Uses the
    # `locale` (country) field from LANGUAGES, where the language maps to its
    # country (en -> gb, ja -> jp, ...); unknown codes pass through unchanged.
    # Defaults to the current locale.
    #
    #   Lux.locale.flag_url(:hr)   # "https://flagcdn.com/hr.svg"
    #   Lux.locale.flag_url(:en)   # "https://flagcdn.com/gb.svg"
    def flag_url(lang = nil)
      code = (lang || current).to_s
      code = LANGUAGES.dig(code, :locale) || code
      "https://flagcdn.com/#{code}.svg"
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

    def t(key = nil, locale: nil, language: nil, fallback: nil, **vars)
      return current if key.nil?   # bare t() -> current (or default) locale

      key = key.to_s
      raise ArgumentError, 'blank key' if key.empty?
      locale ||= language   # `language:` is an alias for `locale:`

      # `t('/main/legal/policy.html')` -> whole view file with the locale
      # inserted before the extension: app/views/main/legal/policy.<locale>.html
      return view_doc(key, locale: locale, fallback: fallback, **vars) if key.start_with?('/')

      # `t('md:legal.terms')` -> whole file <dir>/md/legal/terms.<locale>.md
      return file_doc(key, locale: locale, fallback: fallback, **vars) if key.include?(':')

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

      if @store
        @store.set(lc, ns, subkey, value)
      else
        file_set(ns, lc, subkey, value)
      end
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
    # registered handler -> external store -> flat-file lookup.
    def resolve(ns, subkey, lc)
      if @namespaces && (handler = @namespaces[ns])
        out = handler.call(subkey, lc)
        return out unless out.nil?
      end
      if @store
        out = @store.get(lc, ns, subkey)
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
      dir.join(ns.to_s, "#{lc}.txt")
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

    # Whole-file lookup for `t('<ext>:<dotted.path>')`. Prefix is the file
    # extension; the path's leading segments are folders and the last is the
    # filename, rooted at `dir/<ext>`. Same default-locale fallback, missing
    # marker and interpolation as the line lookup, but the value is the
    # entire file (raw).
    def file_doc(key, locale: nil, fallback: nil, **vars)
      ext, path = key.split(':', 2)
      raise ArgumentError, "blank path in #{key.inspect}" if path.to_s.empty?
      lc = (locale || current).to_sym

      val   = read_doc(ext, path, lc)
      val   = read_doc(ext, path, default) if val.nil? && lc != default
      val ||= fallback
      return "[#{key}]" if val.nil?

      vars.empty? ? val : (val.to_s % vars rescue val)
    end

    def read_doc(ext, path, lc)
      file = inside!(dir, dir.join(ext, "#{path.tr('.', '/')}.#{lc}.#{ext}"))
      file.exist? ? file.read : nil
    end

    # Whole-file lookup for `t('/main/legal/policy.html')`. Rooted at the
    # views dir, the locale is inserted before the final extension:
    # `/main/legal/policy.html` -> app/views/main/legal/policy.<locale>.html.
    # For localized content kept alongside templates rather than under `dir`.
    # Same default-locale fallback, missing marker and interpolation.
    def view_doc(key, locale: nil, fallback: nil, **vars)
      lc = (locale || current).to_sym

      val   = read_view(key, lc)
      val   = read_view(key, default) if val.nil? && lc != default
      val ||= fallback
      return "[#{key}]" if val.nil?

      vars.empty? ? val : (val.to_s % vars rescue val)
    end

    def read_view(path, lc)
      ext  = File.extname(path)            # '.html'
      base = path.delete_suffix(ext)       # '/main/legal/policy'
      root = Pathname.new(views_root)
      file = inside!(root, root.join("#{base.delete_prefix('/')}.#{lc}#{ext}"))
      file.exist? ? file.read : nil
    end

    # Doc keys become file paths. A `..` segment or an absolute path (join
    # drops the root) would read outside it, so check where the file resolved.
    def inside! root, file
      base = File.expand_path(root.to_s)
      return file if File.expand_path(file.to_s).start_with?(base + '/')

      raise ArgumentError, "path escapes #{root}: #{file}"
    end

    def views_root
      (Lux.current.var.views_root rescue nil) || './app/views'
    end

    # Load -> merge subkey -> sort -> atomic rewrite -> drop cache row.
    def file_set(ns, lc, subkey, value)
      path = file_path(ns, lc)
      path.dirname.mkpath unless path.dirname.exist?

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

# Route-scope locale policy. Records whether the request is localized (and
# whether the prefix is forced) on Lux.current, then enforces the URL shape
# where it is declared. Outside a `localized` scope nothing is enforced, so a
# page is not localized unless it says so.
#
#   localized                    # prefix optional; the default locale stays bare
#   localized force: true        # /foo -> /<current>/foo, default included
#   localized geo: false         # ... but do not IP-geo-redirect a first visit
#   localized(false) do ... end  # /en/admin -> /admin
#
# A true scope also sends a first-time visitor (no /xx prefix, no remembered
# choice) to their IP-geo country's locale - see `first_visit_locale`.
#
# `Lux.locale.detect` must have run (typically in a before filter) so the
# prefix is peeled and nav.locale is populated. An un-localized scope has to
# be declared before a force: true one - the first dispatch ends routing.
module Lux
  class Application
    def localized value = true, force: false, geo: true, &block
      return if lux.response.body?

      # opts-hash first arg: localized(force: true) / localized(geo: false)
      if value.is_hash?
        force = value[:force] unless value[:force].nil?
        geo   = value[:geo]   unless value[:geo].nil?
        value = true
      end

      lux[:locale_localized] = value
      lux[:locale_force]     = force
      lux[:locale_geo]       = geo

      if value
        if !lux.nav.locale
          # no /xx prefix: route a first-time visitor by IP-geo country, else
          # leave the bare default (non-forced) or send a forced scope to it.
          if (loc = first_visit_locale)
            redirect_to Lux.locale.path(localized_target, locale: loc)
          elsif force
            redirect_to Lux::Utils::Url.locale(Lux.locale.current)
          end
        elsif !force && lux.nav.locale.to_s == Lux.locale.default.to_s
          # not forced: the default locale is canonical without the prefix
          redirect_to localized_target
        end
      elsif lux.nav.locale
        redirect_to localized_target
      end

      instance_exec(&block) if block
    end

    private

    # A non-default locale to send a first-time visitor to, from IP-geo country.
    # `localized geo: false` opts a scope out; nil once the browser remembers a
    # choice, so it only fires on the first hit.
    def first_visit_locale
      return nil unless lux[:locale_geo]
      return nil unless lux.session[:locale].to_s.empty?

      loc = Lux.locale.geo_locale
      loc if loc && loc.to_s != Lux.locale.default.to_s
    end

    # nav.path is already prefix-free (detect peeled it); keep the query string.
    def localized_target
      path = lux.nav.path.join('/')
      path = path.empty? ? '/' : "/#{path}".sub(%r{/+\z}, '')
      qs   = lux.request.query_string.to_s
      qs.empty? ? path : "#{path}?#{qs}"
    end
  end
end
