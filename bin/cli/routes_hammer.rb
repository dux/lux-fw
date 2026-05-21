task :routes do
  desc 'Print mounted route tree (verb, path, target, source)'
  needs :app
  opt :verbose, alias: :v, type: :boolean, default: false, desc: 'Show source location for each route'

  proc do |opts|
    entries = Lux.app.dump_routes

    if entries.empty?
      puts '(no routes registered)'
      next
    end

    verb_w = entries.map { |e| e.verb.to_s.length }.max
    path_w = entries.map { |e| e.path.to_s.length }.max
    tgt_w  = entries.map { |e| e.target.to_s.length }.max

    entries.each do |e|
      line = '%-*s  %-*s  %-*s' % [verb_w, e.verb, path_w, e.path, tgt_w, e.target]
      line += '  %s' % e.source.to_s.colorize(:white) if opts[:verbose] && e.source
      puts line
    end

    puts
    puts ('%d route%s' % [entries.length, entries.length == 1 ? '' : 's']).colorize(:blue)
  end
end
