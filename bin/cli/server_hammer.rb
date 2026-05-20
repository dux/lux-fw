task :server do
  desc 'Start web server'
  alt :s
  opt :port,  alias: :p, desc: 'Port number'
  opt :env,   alias: :e, desc: 'Environment (test, dev, prod)'
  opt :rerun, alias: :r, type: :boolean, default: false, desc: 'Rerun app on every file change'

  proc do |opts|
    trap('SIGINT') { error 'ctrl+c exit' }

    ENV['RACK_ENV']    = opts[:env] if opts[:env]
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
