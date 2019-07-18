Lux.app do
  before do
    Thread.current[:db_q] = { time: 0.0, cnt: 0, list:{} }
  end

  after do
    next unless Thread.current[:db_q]
    Lux.log " #{Thread.current[:db_q][:cnt]} DB queries, #{(Thread.current[:db_q][:time]*1000).round(1)} ms" if Thread.current[:db_q][:cnt] > 0

    # if params[:sql] == 'true'
    #   require 'niceql'

    #   sql = Thread.current[:db_q]
    #   # r sql

    #   body = HtmlTagBuilder.tag :div do |n|
    #     n.h2 "SQL stats"
    #     n.h4 "Query count: #{sql[:cnt]}"
    #     n.h4 "Time in ms: #{(sql[:time] * 1000).round(1)}"

    #     for _, q in sql[:list]
    #       n._box do |n|
    #         title  = q[:caller].split(':in ').first.sub(Lux.root.to_s, '.')
    #         title += " - (cnt: #{q[:cnt]})" if q[:cnt] > 1
    #         n.small title

    #         sql = q[:sql]
    #         sql = sql.gsub '[0;33;49m', ''
    #         n.pre Niceql::Prettifier.prettify_sql sql
    #       end
    #     end
    #   end

    #   response.render_inline body: body
    #   # response.body = Thread.current[:db_q]

    # end
  end
end
