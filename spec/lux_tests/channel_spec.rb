require 'spec_helper'

describe Lux::Channel do
  before { Lux::Channel.reset! }
  after  { Lux::Channel.reset! }

  describe 'publish / subscribe' do
    it 'delivers messages to subscribers of the same channel' do
      q = Queue.new
      Lux::Channel.subscribe(:foo, q)
      Lux::Channel[:foo].push(value: 1)
      msg = q.pop
      expect(msg[:channel]).to eq('foo')
      expect(msg[:data]).to eq(value: 1)
    end

    it 'fans out to every queue on a channel' do
      a = Queue.new
      b = Queue.new
      Lux::Channel.subscribe(:foo, a)
      Lux::Channel.subscribe(:foo, b)
      Lux::Channel[:foo].push(:hello)
      expect(a.pop[:data]).to eq(:hello)
      expect(b.pop[:data]).to eq(:hello)
    end

    it 'does not deliver to other channels' do
      q = Queue.new
      Lux::Channel.subscribe(:foo, q)
      Lux::Channel[:bar].push(:nope)
      expect(q.empty?).to be true
    end

    it 'normalises channel names to strings' do
      q = Queue.new
      Lux::Channel.subscribe(:foo, q)
      Lux::Channel['foo'].push(:ok)
      expect(q.pop[:data]).to eq(:ok)
    end
  end

  describe 'unsubscribe' do
    it 'stops further delivery and cleans empty channels' do
      q   = Queue.new
      sub = Lux::Channel.subscribe(:foo, q)
      sub.close
      Lux::Channel[:foo].push(:nope)
      expect(q.empty?).to be true
      expect(Lux::Channel.channels).not_to include('foo')
    end
  end

  describe 'Lux.channel shortcut' do
    it 'returns a Publisher that pushes to the named channel' do
      q = Queue.new
      Lux::Channel.subscribe('alerts', q)
      Lux.channel('alerts').push(level: :error)
      expect(q.pop[:data]).to eq(level: :error)
    end
  end

  describe 'subscriber_count' do
    it 'reports the active subscriber count per channel' do
      q1 = Queue.new
      q2 = Queue.new
      Lux::Channel.subscribe(:x, q1)
      Lux::Channel.subscribe(:x, q2)
      expect(Lux::Channel.subscriber_count(:x)).to eq(2)
    end
  end
end
