class ApplicationApi < Lux::Api
  mount_on '/api'

  ###

  rescue_from 405, '$ not found'

  rescue_from :all do |error|
    ap [error.message, error.backtrace.reject{ |_| _.include?('/.rvm/') }] unless $no_error_print

    response.error 'Error happens', status: 500
  end

  rescue_from :named_error, 'Named error example'

  ###

  annotation :anonymous do
    @anonymous_ok = 12345
  end

  ###

  before do
    @_time = Time.now
  end

  after do
    response[:ip] = @api.request ? @api.request.ip : '1.2.3.4'

    if @_time
      response.meta :speed_ms, ((Time.now - @_time)*1000).round(3) unless ENV['RACK_ENV'] == 'test'
    end
  end

  after_auto_mount do |nav, opts|
    if nav[2] && nav.first == 'some_company'
      opts[:params][:company] = nav.shift
    end
  end
end
