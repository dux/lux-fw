# Server diagnostics served at /lux by WebCommonRoutes#server_info: database
# table sizes and system info. Dev or a global admin only - it exposes request ENV.

module ServerInfo
  extend self

  def report
    stats = Lux.cache.fetch 'lux-server-info', ttl: 300 do
      info = []
      info.push 'BASE SERVER STATS'
      info.push '* Ruby version: %s (%s)' % [`ruby -v`.chomp, `ruby -r rbconfig -e "puts RbConfig::CONFIG['LIBS']"`.chomp]
      info.push '* Lux env: %s' % Lux.env
      info.push '* RAM usage now: %s MB for pid %s' % [`ps -o rss= -p #{Process.pid}`.to_i / 1000, Process.pid]
      info.push '* Thread started %s, %s' % [Lux.started_at, Time.ago(Lux.started_at)]
      Lux::Db.connections.each { db_info info, _1 }
      info.join $/
    end

    # per request, never cached - it is the viewer's own env
    env = Lux.current.request.env.reject { ! [String, Boolean, Integer].include?(_2.class) || _1.downcase.include?('cookie') }
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
