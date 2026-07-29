require 'test_helper'

describe Lux::Browser::Channel do
  before { Lux::Browser::Channel.reset! }
  after  { Lux::Browser::Channel.reset! }

  describe 'publish / subscribe' do
    it 'delivers messages to subscribers of the same channel' do
      q = Queue.new
      Lux::Browser::Channel.subscribe('test:foo', q)
      Lux::Browser::Channel['test:foo'].push(value: 1)
      msg = q.pop
      _(msg[:channel]).must_equal 'test:foo'
      _(msg[:data]).must_equal({ value: 1 })
    end

    it 'fans out to every queue on a channel' do
      a = Queue.new
      b = Queue.new
      Lux::Browser::Channel.subscribe('test:foo', a)
      Lux::Browser::Channel.subscribe('test:foo', b)
      Lux::Browser::Channel['test:foo'].push(:hello)
      _(a.pop[:data]).must_equal :hello
      _(b.pop[:data]).must_equal :hello
    end

    it 'does not deliver to other channels' do
      q = Queue.new
      Lux::Browser::Channel.subscribe('test:foo', q)
      Lux::Browser::Channel['test:bar'].push(:nope)
      _(q.empty?).must_equal true
    end

    it 'normalises channel names to strings' do
      q = Queue.new
      Lux::Browser::Channel.subscribe(:'test:foo', q)
      Lux::Browser::Channel['test:foo'].push(:ok)
      _(q.pop[:data]).must_equal :ok
    end

    it 'carries no message id - nothing is replayed' do
      q = Queue.new
      Lux::Browser::Channel.subscribe('test:foo', q)
      Lux::Browser::Channel['test:foo'].push(:a)
      refute_includes q.pop.keys, :id
    end
  end

  describe 'unsubscribe' do
    it 'stops further delivery and cleans empty channels' do
      q   = Queue.new
      sub = Lux::Browser::Channel.subscribe('test:foo', q)
      sub.close
      Lux::Browser::Channel['test:foo'].push(:nope)
      _(q.empty?).must_equal true
      refute_includes Lux::Browser::Channel.channels, 'test:foo'
    end
  end

  # The channel name is the audience, so a bare ref must never become one.
  describe 'channel_name' do
    Target = Struct.new(:ref)

    it 'derives "<model>:<ref>" from anything with a ref' do
      _(Lux::Browser::Channel.channel_name(Target.new('abc123'))).must_equal 'target:abc123'
    end

    # underscore would give "admin/report", and "/" is not a legal channel name -
    # /_lux_/stream drops it, so the push would vanish without an error.
    module Ns; Report = Struct.new(:ref); end

    it 'keeps a namespaced model addressable' do
      name = Lux::Browser::Channel.channel_name(Ns::Report.new('xyz'))

      _(name).must_equal 'ns:report:xyz'
      _(Lux::Browser::Mount::CHANNEL_NAME.match?(name)).must_equal true
    end

    it 'takes a prefixed string or symbol as-is' do
      _(Lux::Browser::Channel.channel_name('user:1')).must_equal 'user:1'
      _(Lux::Browser::Channel.channel_name(:'org:2')).must_equal 'org:2'
    end

    it 'refuses an unprefixed name' do
      err = _{ Lux::Browser::Channel.channel_name('abc123') }.must_raise ArgumentError
      _(err.message).must_match(/needs a prefix/)
    end

    it 'refuses something it cannot derive a channel from' do
      err = _{ Lux::Browser::Channel.channel_name(42) }.must_raise ArgumentError
      _(err.message).must_match(/cannot derive/)
    end

    it 'is what [] and Lux.channel use' do
      q = Queue.new
      Lux::Browser::Channel.subscribe('target:xyz', q)
      Lux.channel(Target.new('xyz')).push(ok: true)
      _(q.pop[:data]).must_equal({ ok: true })
    end
  end

  describe 'Lux.channel shortcut' do
    it 'returns a Publisher that pushes to the named channel' do
      q = Queue.new
      Lux::Browser::Channel.subscribe('app:alerts', q)
      Lux.channel('app:alerts').push(level: :error)
      _(q.pop[:data]).must_equal({ level: :error })
    end
  end

  describe 'subscriber_count' do
    it 'reports the active subscriber count per channel' do
      q1 = Queue.new
      q2 = Queue.new
      Lux::Browser::Channel.subscribe('test:x', q1)
      Lux::Browser::Channel.subscribe('test:x', q2)
      _(Lux::Browser::Channel.subscriber_count('test:x')).must_equal 2
    end
  end

  # One config key picks the backend; Channel itself never names one.
  describe 'broker selection' do
    def build url
      Lux::Browser::Channel::Broker.build url
    end

    it 'defaults to memory when unset' do
      _(build(nil)).must_be_instance_of  Lux::Browser::Channel::MemoryBroker
      _(build('')).must_be_instance_of   Lux::Browser::Channel::MemoryBroker
    end

    it 'picks memory explicitly' do
      _(build('memory:')).must_be_instance_of Lux::Browser::Channel::MemoryBroker
    end

    it 'picks pg for both postgres spellings and defaults the db name' do
      _(build('postgres:')).must_be_instance_of      Lux::Browser::Channel::PgBroker
      _(build('postgresql:')).must_be_instance_of    Lux::Browser::Channel::PgBroker
      _(build('postgres:').db_name).must_equal       :main
      _(build('postgres:events').db_name).must_equal :events
    end

    it 'raises on an unknown scheme, naming the known ones' do
      err = _{ build('redis://localhost') }.must_raise ArgumentError
      _(err.message).must_match(/unknown channel_url scheme "redis"/)
      _(err.message).must_match(/memory/)
    end

    # There is no pool to publish through, so name a Lux DB instead.
    it 'refuses a full postgres connection URL' do
      err = _{ build('postgres://localhost/somedb') }.must_raise ArgumentError
      _(err.message).must_match(/lux_db_name/)
    end

    it 'routes publish through whatever broker is set' do
      seen   = []
      fake   = Class.new(Lux::Browser::Channel::Broker) do
        define_method(:publish) { |name, data| seen << [name, data]; true }
      end.new

      Lux::Browser::Channel.broker = fake
      Lux::Browser::Channel['test:foo'].push(:x)
      _(seen).must_equal [['test:foo', :x]]
    end

    it 'memory broker delivers locally' do
      q = Queue.new
      Lux::Browser::Channel.broker = Lux::Browser::Channel::MemoryBroker.new
      Lux::Browser::Channel.subscribe('test:foo', q)
      Lux::Browser::Channel['test:foo'].push(:hi)
      _(q.pop[:data]).must_equal :hi
    end

    it 'the base contract requires publish and no-ops the rest' do
      base = Lux::Browser::Channel::Broker.new
      _{ base.publish('test:x', 1) }.must_raise NotImplementedError
      _(base.listen!).must_equal     false
      _(base.stop!).must_equal       false
      _(base.after_fork!).must_equal false
      _(base.listening?).must_equal  false
    end
  end

  describe 'session_channels' do
    it 'is unset by default, so no stream can open' do
      _(Lux::Browser::Channel.session_channels).must_be_nil
      _(Lux::Browser::Channel.channels_for(nil)).must_equal []
    end

    it 'returns what the resolver gives, as strings' do
      Lux::Browser::Channel.session_channels { |_lux| [:'user:1', 'org:2'] }
      _(Lux::Browser::Channel.channels_for(nil)).must_equal ['user:1', 'org:2']
    end

    it 'passes the lux context through' do
      seen = nil
      Lux::Browser::Channel.session_channels { |lux| seen = lux; [] }
      Lux::Browser::Channel.channels_for(:ctx)
      _(seen).must_equal :ctx
    end

    it 'wraps a single channel and drops blanks and duplicates' do
      Lux::Browser::Channel.session_channels { |_lux| 'user:1' }
      _(Lux::Browser::Channel.channels_for(nil)).must_equal ['user:1']

      Lux::Browser::Channel.session_channels { |_lux| ['user:1', '', nil, 'user:1'] }
      _(Lux::Browser::Channel.channels_for(nil)).must_equal ['user:1']
    end

    it 'yields nothing for an anonymous visitor' do
      Lux::Browser::Channel.session_channels { |_lux| [] }
      _(Lux::Browser::Channel.channels_for(nil)).must_equal []
    end

    it 'yields nothing when the resolver raises' do
      Lux::Browser::Channel.session_channels { raise 'boom' }
      _(Lux::Browser::Channel.channels_for(nil)).must_equal []
    end

    it 'is cleared by reset!' do
      Lux::Browser::Channel.session_channels { ['user:1'] }
      Lux::Browser::Channel.reset!
      _(Lux::Browser::Channel.session_channels).must_be_nil
    end
  end

  # A listener thread does not survive fork, but its socket does - a clustered
  # puma loads the app in the master, so every worker used to inherit a LISTEN
  # connection that nothing polled.
  describe 'fork awareness' do
    let(:broker) { Lux::Browser::Channel::PgBroker.new('postgres:main') }

    def fake_inherited_listener b
      b.instance_variable_set :@listen_wanted, true
      b.instance_variable_set :@owner_pid, Process.pid - 1
      b.instance_variable_set :@thread, Thread.new { sleep 5 }
      b
    end

    it 'does not call an inherited thread ours' do
      b = fake_inherited_listener broker
      _(b.listening?).must_equal false
      b.stop!
    end

    it 'starts a listener of its own after a fork' do
      b = fake_inherited_listener broker
      _(b.after_fork!).must_equal true
      _(b.instance_variable_get(:@owner_pid)).must_equal Process.pid
      _(b.listening?).must_equal true
      b.stop!
    end

    # Closing it would UNLISTEN and terminate the connection the parent is
    # still reading - we share it at the OS level.
    it 'lets go of the inherited connection without touching it' do
      conn = Object.new
      def conn.close; raise 'must not close the parent connection'; end
      def conn.async_exec(*); raise 'must not touch the parent connection'; end

      b = fake_inherited_listener broker
      b.instance_variable_set :@conn, conn
      b.after_fork!

      _(b.instance_variable_get(:@conn)).wont_be_same_as conn
      b.stop!
    end

    it 'is a no-op where no listener was ever wanted' do
      _(broker.after_fork!).must_equal false
    end
  end
end
