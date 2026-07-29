require 'test_helper'

# The real NOTIFY -> LISTEN -> local_publish round trip, which the rest of the
# suite never touches: test env resolves channel_url to memory, so every other
# channel spec runs entirely in-process and would pass with the PG broker
# completely broken.
#
# Skips itself when there is no reachable DB, so it stays green on a checkout
# without postgres.
describe Lux::Browser::Channel::PgBroker do
  TIMEOUT = 5

  # Own DB name rather than :main - db_spec.rb deletes DB_MAIN and repoints it
  # at sqlite mid-run, which would strand this file's listener. lux-fw has no
  # config.yaml of its own, so point it at the database the suite is migrated
  # into (Lux::Db appends _test under LUX_ENV=test).
  DB_KEY = :channel_test
  ENV['DB_CHANNEL_TEST'] ||= 'postgres:///lux_fw'
  BROKER_URL = 'postgres:%s' % DB_KEY

  class << self
    # Probe through Lux.db, the same path the broker publishes on - probing the
    # raw url_for would check a different database, since Lux::Db appends _test
    # under LUX_ENV=test and url_for does not. rescue Exception because
    # Lux.shell.die exits rather than raising a StandardError, and a missing DB
    # here should skip the file, not kill the run.
    def db_available?
      return @db_available unless @db_available.nil?

      @db_available =
        begin
          Lux.db(DB_KEY).synchronize { |c| c.async_exec('SELECT 1') }
          true
        rescue Exception => e
          warn "channel_pg_spec: skipping, no DB (#{e.class}: #{e.message.lines.first.to_s.strip})"
          false
        end
    end

    # One listener for the whole file: each carries a dedicated PG connection
    # and a thread, and starting five of them proves nothing extra.
    def broker
      @broker ||= Lux::Browser::Channel::PgBroker.new(BROKER_URL).tap(&:listen!)
    end
  end

  def self.wait_until timeout = TIMEOUT
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    sleep 0.02 until yield || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  end

  def wait_until(...) = self.class.wait_until(...)

  # listening? only says the thread is alive - it does not say LISTEN has been
  # issued yet, and a NOTIFY sent before that is simply lost. Round-trip a probe
  # so the assertions below are never racing registration.
  def self.await_ready
    return @ready if defined?(@ready)

    probe = Queue.new
    Lux::Browser::Channel.subscribe 'test:pg-probe', probe

    wait_until do
      broker.publish 'test:pg-probe', 'ping'
      sleep 0.05
      !probe.empty?
    end

    @ready = !probe.empty?
  ensure
    Lux::Browser::Channel.unsubscribe 'test:pg-probe', probe
  end

  def take queue
    wait_until { !queue.empty? }
    refute queue.empty?, 'nothing arrived through NOTIFY within %ss' % TIMEOUT
    queue.pop
  end

  def subscribe name
    Queue.new.tap { |q| (@queues ||= []) << [name, q]; Lux::Browser::Channel.subscribe(name, q) }
  end

  before do
    skip 'no DB reachable' unless self.class.db_available?
    assert self.class.await_ready, 'PG listener never became ready'
    @broker = self.class.broker
  end

  after do
    @queues&.each { |name, q| Lux::Browser::Channel.unsubscribe(name, q) }
  end

  Minitest.after_run do
    @broker&.stop! if @broker
  end

  it 'carries a published message back to a local subscriber' do
    queue = subscribe 'test:pg'

    @broker.publish 'test:pg', { html: 'over the wire', n: 1 }

    msg = take queue
    _(msg[:channel]).must_equal 'test:pg'
    # JSON round trip, so keys come back as strings - this is exactly what a
    # subscriber in another process receives.
    _(msg[:data]).must_equal({ 'html' => 'over the wire', 'n' => 1 })
  end

  it 'carries a plain string payload' do
    queue = subscribe 'test:pg'

    @broker.publish 'test:pg', 'hello'

    _(take(queue)[:data]).must_equal 'hello'
  end

  it 'delivers only to the channel it was published on' do
    mine  = subscribe 'test:pg'
    other = subscribe 'test:pg-other'

    @broker.publish 'test:pg', 'mine'

    _(take(mine)[:data]).must_equal 'mine'
    _(other.empty?).must_equal true
  end

  # Publishing is what a job process does, and it must not need a listener.
  it 'publishes through the pool without a listener of its own' do
    publisher = Lux::Browser::Channel::PgBroker.new(BROKER_URL)
    queue     = subscribe 'test:pg'

    _(publisher.listening?).must_equal false
    _(publisher.publish('test:pg', 'from a publisher-only process')).must_equal true

    _(take(queue)[:data]).must_equal 'from a publisher-only process'
  end

  it 'refuses a payload over the NOTIFY ceiling' do
    err = _{ @broker.publish('test:pg', 'x' * 8000) }.must_raise ArgumentError
    _(err.message).must_match(/too large/)
    _(err.message).must_match(/PgBroker/)
  end
end
