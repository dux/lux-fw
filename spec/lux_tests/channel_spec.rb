require 'test_helper'

describe Lux::Browser::Channel do
  before { Lux::Browser::Channel.reset! }
  after  { Lux::Browser::Channel.reset! }

  describe 'publish / subscribe' do
    it 'delivers messages to subscribers of the same channel' do
      q = Queue.new
      Lux::Browser::Channel.subscribe(:foo, q)
      Lux::Browser::Channel[:foo].push(value: 1)
      msg = q.pop
      _(msg[:channel]).must_equal 'foo'
      _(msg[:data]).must_equal({ value: 1 })
    end

    it 'fans out to every queue on a channel' do
      a = Queue.new
      b = Queue.new
      Lux::Browser::Channel.subscribe(:foo, a)
      Lux::Browser::Channel.subscribe(:foo, b)
      Lux::Browser::Channel[:foo].push(:hello)
      _(a.pop[:data]).must_equal :hello
      _(b.pop[:data]).must_equal :hello
    end

    it 'does not deliver to other channels' do
      q = Queue.new
      Lux::Browser::Channel.subscribe(:foo, q)
      Lux::Browser::Channel[:bar].push(:nope)
      _(q.empty?).must_equal true
    end

    it 'normalises channel names to strings' do
      q = Queue.new
      Lux::Browser::Channel.subscribe(:foo, q)
      Lux::Browser::Channel['foo'].push(:ok)
      _(q.pop[:data]).must_equal :ok
    end
  end

  describe 'unsubscribe' do
    it 'stops further delivery and cleans empty channels' do
      q   = Queue.new
      sub = Lux::Browser::Channel.subscribe(:foo, q)
      sub.close
      Lux::Browser::Channel[:foo].push(:nope)
      _(q.empty?).must_equal true
      refute_includes Lux::Browser::Channel.channels, 'foo'
    end
  end

  describe 'Lux.channel shortcut' do
    it 'returns a Publisher that pushes to the named channel' do
      q = Queue.new
      Lux::Browser::Channel.subscribe('alerts', q)
      Lux.channel('alerts').push(level: :error)
      _(q.pop[:data]).must_equal({ level: :error })
    end
  end

  describe 'subscriber_count' do
    it 'reports the active subscriber count per channel' do
      q1 = Queue.new
      q2 = Queue.new
      Lux::Browser::Channel.subscribe(:x, q1)
      Lux::Browser::Channel.subscribe(:x, q2)
      _(Lux::Browser::Channel.subscriber_count(:x)).must_equal 2
    end
  end

  describe 'message ids' do
    it 'numbers messages per channel from 1' do
      q = Queue.new
      Lux::Browser::Channel.subscribe(:foo, q)
      Lux::Browser::Channel[:foo].push(:a)
      Lux::Browser::Channel[:foo].push(:b)
      _(q.pop[:id]).must_equal 1
      _(q.pop[:id]).must_equal 2
    end

    it 'counts each channel separately' do
      q = Queue.new
      Lux::Browser::Channel.subscribe(:foo, q)
      Lux::Browser::Channel.subscribe(:bar, q)
      Lux::Browser::Channel[:foo].push(:a)
      Lux::Browser::Channel[:bar].push(:b)
      _(q.pop[:id]).must_equal 1
      _(q.pop[:id]).must_equal 1
    end

    it 'keeps the id supplied by the publisher' do
      q = Queue.new
      Lux::Browser::Channel.subscribe(:foo, q)
      Lux::Browser::Channel.local_publish(:foo, :a, 42)
      _(q.pop[:id]).must_equal 42
    end
  end

  describe 'history_since' do
    it 'returns only messages newer than the given id, oldest first' do
      Lux::Browser::Channel[:foo].push(:a)
      Lux::Browser::Channel[:foo].push(:b)
      Lux::Browser::Channel[:foo].push(:c)

      got = Lux::Browser::Channel.history_since(:foo, 1)
      _(got.map { _1[:id] }).must_equal [2, 3]
      _(got.map { _1[:data] }).must_equal [:b, :c]
    end

    it 'retains history without any subscriber' do
      Lux::Browser::Channel[:foo].push(:a)
      _(Lux::Browser::Channel.history_since(:foo, 0).size).must_equal 1
    end

    it 'is empty for an unknown channel' do
      _(Lux::Browser::Channel.history_since(:nope, 0)).must_equal []
    end

    it 'caps retained messages at HISTORY_SIZE, dropping the oldest' do
      total = Lux::Browser::Channel::HISTORY_SIZE + 10
      total.times { Lux::Browser::Channel[:foo].push(_1) }

      got = Lux::Browser::Channel.history_since(:foo, 0)
      _(got.size).must_equal Lux::Browser::Channel::HISTORY_SIZE
      _(got.first[:id]).must_equal 11
      _(got.last[:id]).must_equal total
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
end
