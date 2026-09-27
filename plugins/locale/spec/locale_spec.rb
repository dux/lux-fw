require 'test_helper'
require 'fileutils'
require 'tmpdir'

Lux::Plugin.load File.expand_path('..', __dir__)

describe Lux::Locale do
  def tmp
    @tmp ||= Pathname.new(Dir.mktmpdir('lux-locale-'))
  end

  before do
    Lux::Current.new('http://test-locale')
    %i[@default @available @dir @before_get @before_set @namespaces @store].each do |ivar|
      Lux.locale.instance_variable_set(ivar, nil)
    end
    Lux.locale.reload!

    Lux.locale.dir       = tmp
    Lux.locale.default   = :en
    Lux.locale.available = %i[en de]

    FileUtils.mkdir_p tmp.join('users')
    File.write tmp.join('users/en.txt'), <<~TXT
      welcome: Hi %{name}
      profile.title: Profile
    TXT

    File.write tmp.join('users/de.txt'), <<~TXT
      welcome: Hallo %{name}
    TXT
  end

  after do
    FileUtils.remove_entry tmp if tmp.exist?
  end

  describe '#current' do
    it 'falls back to default when Lux.current.locale is unset' do
      _(Lux.locale.current).must_equal :en
    end

    it 'reads from Lux.current.locale' do
      Lux.current.locale = 'de'
      _(Lux.locale.current).must_equal :de
    end

    it 'raises Unknown for a locale not in available' do
      Lux.current.locale = 'fr'
      assert_raises(Lux::Locale::Unknown) { Lux.locale.current }
    end
  end

  describe '#t' do
    it 'returns the current locale when called with no key' do
      _(Lux.locale.t).must_equal :en
      Lux.current.locale = 'de'
      _(Lux.locale.t).must_equal :de
    end

    it 'looks up dotted keys in the YAML file' do
      _(Lux.locale.t('users.profile.title')).must_equal 'Profile'
    end

    it 'interpolates %{vars}' do
      _(Lux.locale.t('users.welcome', name: 'Joe')).must_equal 'Hi Joe'
    end

    it 'honors an explicit locale: override' do
      _(Lux.locale.t('users.welcome', name: 'Joe', locale: :de)).must_equal 'Hallo Joe'
    end

    it 'falls back to the default locale when key missing in requested' do
      Lux.current.locale = 'de'
      _(Lux.locale.t('users.profile.title')).must_equal 'Profile'
    end

    it 'uses the fallback: arg when nothing matches' do
      _(Lux.locale.t('users.missing', fallback: 'X')).must_equal 'X'
    end

    it 'returns [key] when fully missing' do
      _(Lux.locale.t('users.unknown')).must_equal '[users.unknown]'
    end

    it 'requires a namespace' do
      err = assert_raises(ArgumentError) { Lux.locale.t('hi') }
      assert_match(/namespaced/, err.message)
    end
  end

  describe '#t file loader' do
    before do
      FileUtils.mkdir_p tmp.join('md/legal')
      FileUtils.mkdir_p tmp.join('html')
      File.write tmp.join('md/service.en.md'),       "# Service\n\nWelcome %{name}\n"
      File.write tmp.join('md/legal/terms.en.md'),   "# Terms EN\n"
      File.write tmp.join('md/legal/terms.de.md'),   "# Terms DE\n"
      File.write tmp.join('html/page.en.html'),      "<h1>Page</h1>\n"
    end

    it 'returns the whole file for a single-segment key' do
      _(Lux.locale.t('md:service')).must_equal "# Service\n\nWelcome %{name}\n"
    end

    it 'maps leading segments to folders and the last to the filename' do
      Lux.current.locale = 'de'
      _(Lux.locale.t('md:legal.terms')).must_equal "# Terms DE\n"
    end

    it 'honors an explicit locale: override' do
      _(Lux.locale.t('md:legal.terms', locale: :de)).must_equal "# Terms DE\n"
    end

    it 'falls back to the default locale when the file is missing' do
      Lux.current.locale = 'de'
      _(Lux.locale.t('md:service')).must_equal "# Service\n\nWelcome %{name}\n"
    end

    it 'returns [key] when fully missing' do
      _(Lux.locale.t('md:unknown')).must_equal '[md:unknown]'
    end

    it 'uses the fallback: arg when nothing matches' do
      _(Lux.locale.t('md:unknown', fallback: 'X')).must_equal 'X'
    end

    it 'interpolates %{vars} when passed' do
      _(Lux.locale.t('md:service', name: 'Joe')).must_equal "# Service\n\nWelcome Joe\n"
    end

    it 'resolves the prefix as the file extension' do
      _(Lux.locale.t('html:page')).must_equal "<h1>Page</h1>\n"
    end

    it 'raises on a blank path' do
      err = assert_raises(ArgumentError) { Lux.locale.t('md:') }
      assert_match(/blank path/, err.message)
    end

    it 'raises when the extension part climbs with ..' do
      # ext '../md' -> <dir>/../md/service.en.../md, outside dir
      err = assert_raises(ArgumentError) { Lux.locale.t('../md:service') }
      assert_match(/path escapes/, err.message)
      assert_raises(ArgumentError) { Lux.locale.t('..:service') }
    end

    # join drops the root for an absolute path, so this has to be caught too
    it 'raises on an absolute path' do
      assert_raises(ArgumentError) { Lux.locale.t('md:/etc/hosts') }
    end
  end

  describe '#t view loader' do
    def views
      @views ||= Pathname.new(Dir.mktmpdir('lux-views-'))
    end

    before do
      Lux.current.var.views_root = views.to_s
      FileUtils.mkdir_p views.join('main/legal')
      File.write views.join('main/legal/policy.en.html'), "<h1>Policy EN %{name}</h1>\n"
      File.write views.join('main/legal/policy.de.html'), "<h1>Policy DE</h1>\n"
    end

    after { FileUtils.remove_entry views if views.exist? }

    it 'inserts the locale before the extension, rooted at views' do
      _(Lux.locale.t('/main/legal/policy.html')).must_equal "<h1>Policy EN %{name}</h1>\n"
    end

    it 'accepts language: as an alias for locale:' do
      _(Lux.locale.t('/main/legal/policy.html', language: :de)).must_equal "<h1>Policy DE</h1>\n"
    end

    it 'falls back to the default locale when the file is missing' do
      Lux.current.locale = 'de'
      File.delete views.join('main/legal/policy.de.html')
      _(Lux.locale.t('/main/legal/policy.html')).must_equal "<h1>Policy EN %{name}</h1>\n"
    end

    it 'interpolates %{vars} when passed' do
      _(Lux.locale.t('/main/legal/policy.html', name: 'Joe')).must_equal "<h1>Policy EN Joe</h1>\n"
    end

    it 'returns [key] when fully missing' do
      _(Lux.locale.t('/main/legal/missing.html')).must_equal '[/main/legal/missing.html]'
    end

    it 'raises when the path climbs with ..' do
      err = assert_raises(ArgumentError) { Lux.locale.t('/main/../../etc/passwd.html') }
      assert_match(/path escapes/, err.message)
    end

    it 'raises on an absolute path' do
      assert_raises(ArgumentError) { Lux.locale.t('//etc/hosts.html') }
    end
  end

  describe '#namespace' do
    it 'wins over the YAML file when handler returns non-nil' do
      Lux.locale.namespace(:users) { |sub, _lc| sub == 'profile.title' ? 'Dynamic' : nil }
      _(Lux.locale.t('users.profile.title')).must_equal 'Dynamic'
    end

    it 'falls through to YAML when handler returns nil' do
      Lux.locale.namespace(:users) { |_sub, _lc| nil }
      _(Lux.locale.t('users.welcome', name: 'Joe')).must_equal 'Hi Joe'
    end

    it 'receives subkey and locale' do
      seen = []
      Lux.locale.namespace(:users) { |sub, lc| seen << [sub, lc]; nil }
      Lux.locale.t('users.welcome', name: 'Joe')
      _(seen).must_equal [['welcome', :en]]
    end
  end

  describe '#before_get' do
    it 'short-circuits the lookup when it returns non-nil' do
      Lux.locale.before_get { |_lc, _key| 'Hijacked' }
      _(Lux.locale.t('users.welcome', name: 'Joe')).must_equal 'Hijacked'
    end

    it 'falls through when nil' do
      Lux.locale.before_get { |_lc, _key| nil }
      _(Lux.locale.t('users.welcome', name: 'Joe')).must_equal 'Hi Joe'
    end
  end

  describe '#set' do
    it 'writes a new key to the text file' do
      Lux.locale.set('users.farewell', 'Bye', locale: :en)
      _(Lux.locale.t('users.farewell')).must_equal 'Bye'

      raw = tmp.join('users/en.txt').read
      _(raw).must_include 'farewell: Bye'
    end

    it 'creates the file when missing' do
      Lux.locale.set('cart.empty', 'Empty', locale: :en)
      assert tmp.join('cart/en.txt').exist?
      _(Lux.locale.t('cart.empty')).must_equal 'Empty'
    end

    it 'sorts keys alphabetically on save' do
      Lux.locale.set('users.zeta',  'Z', locale: :en)
      Lux.locale.set('users.alpha', 'A', locale: :en)
      lines = tmp.join('users/en.txt').read.lines.map(&:chomp).reject(&:empty?)
      _(lines).must_equal lines.sort
    end

    it 'invalidates the in-process cache' do
      Lux.locale.t('users.welcome', name: 'Joe')  # warm cache
      Lux.locale.set('users.welcome', 'Hey %{name}', locale: :en)
      _(Lux.locale.t('users.welcome', name: 'Joe')).must_equal 'Hey Joe'
    end

    it 'runs before_set and stores its return value when non-nil' do
      Lux.locale.before_set { |_lc, _key, v| v.to_s.strip }
      Lux.locale.set('users.foo', "  trimmed  ", locale: :en)
      _(Lux.locale.t('users.foo')).must_equal 'trimmed'
    end

    it 'leaves value untouched when before_set returns nil' do
      Lux.locale.before_set { |_lc, _key, _v| nil }
      Lux.locale.set('users.foo', 'raw', locale: :en)
      _(Lux.locale.t('users.foo')).must_equal 'raw'
    end
  end

  describe '#reload!' do
    it 'forces a re-read of files' do
      Lux.locale.t('users.welcome', name: 'Joe')          # warm
      File.write tmp.join('users/en.txt'), "welcome: Yo %{name}\n"
      Lux.locale.reload!
      _(Lux.locale.t('users.welcome', name: 'Joe')).must_equal 'Yo Joe'
    end
  end

  describe '#store' do
    # Minimal duck for Lux::Locale.store: responds to .get and .set
    def store
      @store ||= Class.new do
        def initialize; @rows = {}; end
        def get(lc, ns, sub);        @rows[[lc, ns, sub]]; end
        def set(lc, ns, sub, value); @rows[[lc, ns, sub]] = value.to_s; end
      end.new
    end

    before { Lux.locale.store = store }

    it 'reads from store before falling back to file' do
      store.set(:en, :users, 'welcome', 'From DB %{name}')
      _(Lux.locale.t('users.welcome', name: 'Joe')).must_equal 'From DB Joe'
    end

    it 'falls through to file when store returns nil' do
      _(Lux.locale.t('users.welcome', name: 'Joe')).must_equal 'Hi Joe'
    end

    it 'writes through store instead of file' do
      Lux.locale.set('users.farewell', 'Bye', locale: :en)
      _(store.get(:en, :users, 'farewell')).must_equal 'Bye'
      refute_includes tmp.join('users/en.txt').read, 'farewell:'
    end
  end
end
