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
end
