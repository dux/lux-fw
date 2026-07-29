require 'test_helper'

describe Lux::Response::Sse do
  Body = Lux::Response::Sse::StreamBody

  before { Lux::Browser::Channel.reset! }
  after  { Lux::Browser::Channel.reset! }

  def format channel, data, id = nil
    Body.new([]).send(:format_event, channel, data, id)
  end

  # #each never returns on its own - it blocks on the queue until the client
  # goes away. Run it on a thread, wait for the frames we expect, then kill it.
  # Yields the running body so a test can publish into a live stream.
  def frames_for body, expect: 1, timeout: 2
    out    = []
    thread = Thread.new { body.each { |frame| out << frame } }

    wait_for(out, expect, timeout)
    yield out if block_given?

    out
  ensure
    thread&.kill
  end

  def wait_for out, size, timeout = 2
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    sleep 0.01 while out.size < size && Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
  end

  describe 'framing' do
    it 'wraps every payload as {channel, data} on the default message event' do
      _(format('foo', { a: 1 })).must_equal %(data: {"channel":"foo","data":{"a":1}}\n\n)
    end

    it 'carries a string payload in the same envelope' do
      _(format('foo', 'hello')).must_equal %(data: {"channel":"foo","data":"hello"}\n\n)
    end

    # A raw newline would end the frame early and corrupt the rest of the
    # stream; JSON escaping is what makes that impossible.
    it 'cannot be broken by a newline in the payload' do
      frame = format('foo', "a\nb")
      _(frame).must_equal %(data: {"channel":"foo","data":"a\\nb"}\n\n)
      _(frame.scan("\n\n").size).must_equal 1
    end

    it 'includes an id line when given one' do
      _(format('foo', 'x', 7)).must_equal %(id: 7\ndata: {"channel":"foo","data":"x"}\n\n)
    end

    it 'omits the id line when there is none' do
      refute_includes format('foo', 'x'), 'id:'
    end

    it 'never emits a per-channel event line, so one connection needs no listeners' do
      refute_includes format('foo', 'x', 1), 'event:'
    end
  end

  describe 'replay' do
    it 'sends nothing but the handshake without a Last-Event-ID' do
      Lux::Browser::Channel[:foo].push('a')

      frames = frames_for Body.new(['foo'])
      _(frames).must_equal [": connected\n\n"]
    end

    it 'replays only what the client missed' do
      3.times { |i| Lux::Browser::Channel[:foo].push("m#{i + 1}") }

      frames = frames_for Body.new(['foo'], 1), expect: 3
      _(frames[1]).must_equal %(id: 2\ndata: {"channel":"foo","data":"m2"}\n\n)
      _(frames[2]).must_equal %(id: 3\ndata: {"channel":"foo","data":"m3"}\n\n)
      _(frames.size).must_equal 3
    end

    it 'streams messages published after the replay' do
      Lux::Browser::Channel[:foo].push('m1')

      frames = frames_for Body.new(['foo'], 0), expect: 2 do |out|
        Lux::Browser::Channel[:foo].push('m2')
        wait_for out, 3
      end

      _(frames[2]).must_equal %(id: 2\ndata: {"channel":"foo","data":"m2"}\n\n)
    end

    # A message can land in the queue after it was already replayed, because
    # #each subscribes before it reads history. Same id, so it must be dropped.
    it 'does not resend a message that was already replayed' do
      Lux::Browser::Channel[:foo].push('m1')
      Lux::Browser::Channel[:foo].push('m2')

      frames = frames_for Body.new(['foo'], 0), expect: 3 do |out|
        Lux::Browser::Channel.local_publish(:foo, 'm2', 2)
        Lux::Browser::Channel.local_publish(:foo, 'm3', 3)
        wait_for out, 4
      end

      _(frames.count { _1.include?('"data":"m2"') }).must_equal 1
      _(frames.last).must_equal %(id: 3\ndata: {"channel":"foo","data":"m3"}\n\n)
    end
  end

  # One connection carries several channels; the client routes on the channel
  # field. This is what lets a session hold exactly one socket.
  describe 'multiplexing' do
    it 'tags each frame with the channel it came from' do
      frames = frames_for Body.new(%w[user:1 org:2]), expect: 1 do |out|
        Lux::Browser::Channel['user:1'].push('mine')
        Lux::Browser::Channel['org:2'].push('ours')
        wait_for out, 3
      end

      _(frames[1]).must_include %("channel":"user:1")
      _(frames[2]).must_include %("channel":"org:2")
    end

    it 'ignores channels the connection did not subscribe to' do
      frames = frames_for Body.new(['user:1']), expect: 1 do |out|
        Lux::Browser::Channel['user:2'].push('not yours')
        sleep 0.1
      end

      _(frames.size).must_equal 1
    end
  end
end
