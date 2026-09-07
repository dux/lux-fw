task :start do
  desc 'Prepare env and autorun app (mount, assets:auto, then Procfile)'
  alt :s
  needs :app
  opt :port, alias: :p, desc: 'Port number (default: $PORT or 3000)'
  opt :prod, type: :boolean, desc: 'Run ./Procfile.prod instead of ./Procfile'
  opt :file, alias: :f, desc: 'Procfile path (overrides --prod)'
  proc do |opts|
    # The dev port is decided once, here, and inherited by every Procfile
    # service: puma binds PORT, rollup serves livereload off LIVERELOAD_PORT.
    # A Procfile line that assigns PORT itself still wins - don't do that.
    port = (opts[:port] || ENV['PORT'] || 3000).to_i
    ENV['PORT']            = port.to_s
    ENV['LIVERELOAD_PORT'] = (35729 + port - 3000).to_s

    hammer 'mount'
    hammer 'assets:auto'

    file = opts[:file] || (opts[:prod] ? './Procfile.prod' : './Procfile')
    # replace this booted process with the lean Procfile runner
    # argv form, not one string - multi arg exec skips the shell, so the whole
    # command line would otherwise be looked up as a single executable name
    exec 'bundle', 'exec', 'lux', 'procfile', '-f', file
  end
end
