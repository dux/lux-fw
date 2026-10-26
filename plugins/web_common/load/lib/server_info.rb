# Server diagnostics served at /lux by WebCommonRoutes#server_info: database
# table sizes and system info. Dev or a global admin only - it exposes request ENV.

module ServerInfo
  extend self

  def report
    # per process, never cached - another worker would report its own pid / RAM
    info = []
    info.push 'BASE SERVER STATS'
    info.push '* Ruby version: %s (%s)' % [RUBY_DESCRIPTION, RbConfig::CONFIG['LIBS']]
    info.push '* Lux env: %s' % Lux.env
    info.push '* RAM usage now: %s MB for pid %s' % [`ps -o rss= -p #{Process.pid}`.to_i / 1000, Process.pid]
    info.push '* Thread started %s, %s' % [Lux.started_at, Time.ago(Lux.started_at)]

    db = Lux.cache.fetch 'lux-server-info', ttl: 300 do
      list = []
      Lux::Db.connections.each { db_info list, _1 }
      list.join $/
    end
    stats = [info.join($/), db].join $/

    # per request, never cached - it is the viewer's own env
    env = Lux.ctx.request.env.select { |k, v| [String, Integer, Boolean].any? { v.is_a?(_1) } && !k.match?(/cookie|authorization/i) }
    [stats, '', 'Current user ENV', env.to_jsonp].join $/
  end

  private

  def db_info info, db
    data = db.fetch(%q[
      SELECT nspname || '.' || relname AS "ref",
        pg_size_pretty(pg_total_relation_size(C.oid)) AS "size"
      FROM pg_class C
      LEFT JOIN pg_namespace N ON (N.oid = C.relnamespace)
      WHERE nspname NOT IN ('pg_catalog', 'information_schema')
        AND C.relkind <> 'i'
        AND nspname !~ '^pg_toast'
      ORDER BY pg_total_relation_size(C.oid) DESC
      ]).to_a

    info.push ''
    info.push 'DB: %s' % db.uri.split('/').last.upcase
    for row in data
      info.push '%s : %s' % [row[:ref].ljust(30), row[:size]]
    end
  end
end
