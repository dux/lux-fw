task :start do
  desc 'Prepare env and autorun app (mount, assets:auto, then Procfile)'
  alt :s
  needs :app
  opt :prod, type: :boolean, desc: 'Run ./Procfile.prod instead of ./Procfile'
  opt :file, alias: :f, desc: 'Procfile path (overrides --prod)'
  proc do |opts|
    hammer 'mount'
    hammer 'assets:auto'

    file = opts[:file] || (opts[:prod] ? './Procfile.prod' : './Procfile')
    # replace this booted process with the lean Procfile runner
    # argv form, not one string - multi arg exec skips the shell, so the whole
    # command line would otherwise be looked up as a single executable name
    exec 'bundle', 'exec', 'lux', 'procfile', '-f', file
  end
end
