require 'json'

module Lux
  class Browser
    module Channel
      # Cross-process bridge for Lux::Browser::Channel.
      #
      # Two switches, both off by default:
      #
      #   PgBroker.enable_publish!   - publishes go through NOTIFY instead of
      #                                in-process fan-out.
      #   PgBroker.enable_listen!    - implies enable_publish! AND starts a
      #                                dedicated PG connection on a background
      #                                thread that LISTENs and re-publishes
      #                                inbound notifications locally.
      #
      # Typical setup:
      #
      #   # Puma workers (publish + receive):
      #   on_worker_boot { Lux::Browser::Channel.pg_listen! }
      #
      #   # Job / rake / one-off processes (publish only):
      #   Lux::Browser::Channel.pg_publish!
      #
      # Caveats:
      # * PG NOTIFY payload is capped at ~7.9 KB (server-side). Anything
      #   larger raises on publish; ship a pointer + fetch detail.
      # * The listening worker holds one dedicated raw PG connection in
      #   LISTEN mode (outside the Sequel pool). Count it against your
      #   max_connections.
      # * No replay - LISTEN/NOTIFY is fire-and-forget.
      # * NOTIFY is database-scoped. Publisher and listener must use the
      #   same Lux DB name (`db_name:` on both calls).
      module PgBroker
        extend self

        PG_CHANNEL ||= 'lux_channel'
        SEP        ||= '|'

        # PG hard limit on NOTIFY payload is 8000 bytes; leave headroom for
        # "<name>|" prefix and protocol overhead.
        MAX_PAYLOAD ||= 7800

        # Reconnect backoff (seconds) for the listener loop.
        BACKOFF_MIN ||= 1
        BACKOFF_MAX ||= 30

        @lock ||= Mutex.new

        def publish_enabled?
          @publish_enabled == true
        end

        def listening?
          @thread&.alive? ? true : false
        end

        # Route Channel.publish through NOTIFY on `db_name`. Idempotent.
        # Use this in processes that only publish (jobs, rake tasks).
        def enable_publish! db_name: :main
          @lock.synchronize do
            @db_name         = db_name
            @publish_enabled = true
          end
          true
        end

        # Enable publish AND start the listener thread on `db_name`. Idempotent.
        # Use this in Puma workers (so they receive what other processes publish).
        def enable_listen! db_name: :main
          @lock.synchronize do
            @db_name         = db_name
            @publish_enabled = true
            return true if @thread&.alive?
            @stop    = false
            @thread  = Thread.new { run_loop }
            @thread.name = 'lux_channel_broker'
          end
          true
        end

        # Stop the listener (if any) and disable NOTIFY-based publishing.
        def stop!
          @lock.synchronize do
            @publish_enabled = false
            @stop            = true
            t                = @thread
            c                = @conn
            @thread          = nil
            @conn            = nil

            if c
              begin c.async_exec("UNLISTEN *") rescue nil end
              begin c.close                    rescue nil end
            end
            t&.kill
          end
          true
        end

        # Send a NOTIFY on the configured DB. Uses a pooled Sequel connection -
        # returns immediately. The matching listener (in any process that called
        # enable_listen! on the same db_name) will re-publish locally.
        def publish name, data
          payload = "#{name}#{SEP}#{data.is_a?(String) ? data : JSON.generate(data)}"
          raise ArgumentError, "channel payload too large (#{payload.bytesize} > #{MAX_PAYLOAD})" if payload.bytesize > MAX_PAYLOAD

          Lux.db(@db_name || :main).synchronize do |conn|
            conn.async_exec("NOTIFY #{PG_CHANNEL}, #{conn.escape_literal(payload)}")
          end
          true
        end

        private

        def run_loop
          backoff = BACKOFF_MIN

          until @stop
            begin
              @conn = open_conn
              @conn.async_exec("LISTEN #{PG_CHANNEL}")
              backoff = BACKOFF_MIN

              until @stop
                @conn.wait_for_notify(5) do |_chan, _pid, payload|
                  dispatch(payload)
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
          begin @conn&.async_exec("UNLISTEN *") rescue nil end
          begin @conn&.close                    rescue nil end
          @conn = nil
        end

        def dispatch payload
          name, raw = payload.split(SEP, 2)
          return unless name && raw

          data = begin
            JSON.parse(raw)
          rescue JSON::ParserError
            raw
          end

          # Direct local fan-out - bypass Channel.publish to avoid re-NOTIFY loop.
          Lux::Browser::Channel.local_publish(name, data)
        end

        def open_conn
          require 'pg'
          url = Lux::Db.url_for(@db_name) or raise "Lux::Db.url_for(#{@db_name.inspect}) returned nil"
          PG.connect(url)
        end
      end
    end
  end
end
