require 'json'
require_relative 'base'

module Lux
  class Browser
    module Channel
      # Cross-process fan-out over PG LISTEN/NOTIFY.
      #
      #   channel_url: postgres:        # Lux DB :main
      #   channel_url: postgres:main    # same, explicit
      #   channel_url: postgres:events  # a different Lux DB name
      #
      # Publishing works anywhere - it borrows a pooled Sequel connection and
      # returns. Only a process that holds browser connections needs listen!,
      # which is why Lux::Boot starts it for Lux.runtime.web? and nowhere else.
      #
      # Caveats:
      # * NOTIFY payload is capped at ~7.9 KB server-side. Anything larger
      #   raises on publish; ship a pointer and let the client fetch detail.
      # * A listening process holds one dedicated raw PG connection in LISTEN
      #   mode, outside the Sequel pool. Count it against max_connections.
      # * Fire-and-forget. A process started after a NOTIFY never sees it, and
      #   nothing is replayed to a reconnecting browser.
      # * NOTIFY is database-scoped: publisher and listener must name the same
      #   Lux DB.
      # * The listener thread does not survive fork - see after_fork!.
      class PgBroker < Broker
        PG_CHANNEL ||= 'lux_channel'
        SEP        ||= '|'

        # PG's hard limit is 8000 bytes; leave headroom for the "<name>|"
        # prefix and protocol overhead.
        MAX_PAYLOAD ||= 7800

        # Reconnect backoff (seconds) for the listener loop.
        BACKOFF_MIN ||= 1
        BACKOFF_MAX ||= 30

        attr_reader :db_name

        def initialize url = nil
          super

          rest = @url.split(':', 2)[1].to_s

          if rest.start_with?('//')
            raise ArgumentError,
              "channel_url #{@url.inspect}: use postgres:<lux_db_name> (e.g. postgres:main). " \
              'A full connection URL has no pool to publish through - name a Lux DB instead.'
          end

          @db_name = (rest.empty? ? 'main' : rest).to_sym
          @lock    = Mutex.new
        end

        # Uses a pooled connection and returns immediately. Every process
        # LISTENing on the same DB re-publishes it locally.
        def publish name, data
          payload = '%s%s%s' % [name, SEP, data.is_a?(String) ? data : JSON.generate(data)]

          if payload.bytesize > MAX_PAYLOAD
            raise ArgumentError,
              "channel payload too large for #{self.class} (#{payload.bytesize} > #{MAX_PAYLOAD} bytes) - push a pointer, not a page"
          end

          Lux.db(@db_name).synchronize do |conn|
            conn.async_exec('NOTIFY %s, %s' % [PG_CHANNEL, conn.escape_literal(payload)])
          end

          true
        end

        # Start the LISTEN thread. Idempotent per process - and "per process" is
        # the whole point: a listener started before a fork is not a listener in
        # the child.
        def listen!
          @lock.synchronize do
            @listen_wanted = true
            return true if @owner_pid == Process.pid && @thread&.alive?

            # Inherited from a parent: the thread is gone, but @conn names a
            # socket the parent is still reading. Drop the reference and leave
            # it alone - closing it here would UNLISTEN and terminate the
            # parent's connection, which we share at the OS level.
            @conn = nil unless @owner_pid == Process.pid

            @stop        = false
            @owner_pid   = Process.pid
            @thread      = Thread.new { run_loop }
            @thread.name = 'lux_channel_broker'
          end

          true
        end

        # Only true for a listener this process started. State inherited across
        # a fork names a thread that no longer exists.
        def listening?
          (@owner_pid == Process.pid && @thread&.alive?) ? true : false
        end

        # Re-arm in a freshly forked child. A clustered server loads the app -
        # and so starts the listener - in the master, so without this every
        # worker holds an inherited LISTEN socket that nothing polls and no
        # message ever reaches a browser. Called from Lux::Boot's puma hook.
        #
        # No-op in the process that started the listener, and in any process
        # that never wanted one.
        def after_fork!
          return false unless @listen_wanted
          return false if @owner_pid == Process.pid

          listen!
        end

        def stop!
          @lock.synchronize do
            @listen_wanted = false
            @stop          = true
            t              = @thread
            c              = @conn
            @thread        = nil
            @conn          = nil
            @owner_pid     = nil

            if c
              begin c.async_exec('UNLISTEN *') rescue nil end
              begin c.close                    rescue nil end
            end

            t&.kill
          end

          true
        end

        private

        def run_loop
          backoff = BACKOFF_MIN

          until @stop
            begin
              @conn = open_conn
              @conn.async_exec('LISTEN %s' % PG_CHANNEL)
              backoff = BACKOFF_MIN

              until @stop
                @conn.wait_for_notify(5) do |_chan, _pid, payload|
                  dispatch payload
                end
              end
            rescue => e
              Lux.shell.info "Channel broker: #{e.class} #{e.message} - reconnecting in #{backoff}s" rescue nil
              begin @conn&.close rescue nil end
              @conn = nil
              sleep backoff unless @stop
              backoff = [backoff * 2, BACKOFF_MAX].min
            end
          end
        ensure
          begin @conn&.async_exec('UNLISTEN *') rescue nil end
          begin @conn&.close                    rescue nil end
          @conn = nil
        end

        def dispatch payload
          name, raw = payload.split(SEP, 2)
          return unless name && raw

          data = begin
            JSON.parse raw
          rescue JSON::ParserError
            raw
          end

          # Local fan-out directly - going back through Channel.publish would
          # bounce this straight into another NOTIFY.
          Lux::Browser::Channel.local_publish name, data
        end

        # Built from the very connection publish uses, not from
        # Lux::Db.url_for. Those two disagree wherever Lux::Db rewrites a URL -
        # under LUX_ENV=test it appends _test to the database name, so url_for
        # said "lux_fw_test" while the pool was on "lux_fw_test_test". NOTIFY is
        # database-scoped, so a publisher and listener split that way simply
        # never meet, silently. Taking both from one place makes that
        # impossible rather than merely unlikely.
        def open_conn
          require 'pg'
          opts = Lux.db(@db_name).opts

          PG.connect(
            dbname:   opts[:database],
            host:     opts[:host],
            port:     opts[:port],
            user:     opts[:user],
            password: opts[:password],
          )
        end
      end
    end
  end
end
