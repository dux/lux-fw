task :server do
  desc 'Start web server'
  alt :s
  opt :port,   alias: :p, desc: 'Port number'
  opt :env,    alias: :e, desc: 'Environment (test, dev, prod)'
  opt :rerun,  alias: :R, type: :boolean, default: false, desc: 'Rerun app on every file change'
  opt :log,    alias: :l, placeholder: 't/f', desc: 'LUX_LOG mode'
  opt :errors, alias: :x, placeholder: 't/f', desc: 'LUX_ERRORS mode'
  opt :reload, alias: :r, placeholder: 't/f', desc: 'LUX_RELOAD mode'

  proc do |opts|
    trap('SIGINT') { error 'ctrl+c exit' }

    # t -> true, f -> false; otherwise pass-through (true/false accepted as-is).
    expand_mode = ->(v) { { 't' => 'true', 'f' => 'false' }[v.to_s.downcase] || v.to_s }

    ENV['RACK_ENV']    = opts[:env] if opts[:env]
    ENV['LUX_LOG']     = expand_mode.(opts[:log])    if opts[:log]
    ENV['LUX_ERRORS']  = expand_mode.(opts[:errors]) if opts[:errors]
    ENV['LUX_RELOAD']  = expand_mode.(opts[:reload]) if opts[:reload]
    ENV['LUX_LOG']    ||= 'true'
    ENV['LUX_ERRORS'] ||= 'true'
    ENV['LUX_RELOAD'] ||= 'true'

    port = opts[:port] || ENV.fetch('PORT', '3000')
    ENV['PORT'] = port.to_s

    flags = %w(LUX_LOG LUX_ERRORS LUX_RELOAD).map { |k| "#{k}=#{ENV[k]}" }.join(' ')
    base  = "RACK_ENV=#{ENV['RACK_ENV']} #{flags} bundle exec puma"

    if opts[:rerun]
      sh "find #{LUX_ROOT} . -name *.rb | entr -r #{base} -p #{port}"
    else
      sh "#{base} -p #{port}"
    end
  end
end
