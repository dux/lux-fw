# frozen_string_literal: true

# 400: for bad parameter request or similar
BadRequestError   ||= Class.new(StandardError)

# 401: for unauthorized access
UnauthorizedError ||= Class.new(StandardError)

# 403: for unalloed access
ForbidenError     ||= Class.new(StandardError)

# 404: for not found pages
NotFoundError     ||= Class.new(StandardError)

# 503: for too many requests at the same time
RateLimitError    ||= Class.new(StandardError)

module Lux::Error
  extend self

  def try name=nil
    begin
      yield
    rescue Exception => e
      Lux.current.response.status 500

      key = log e

      if Lux.config(:show_server_errors)
        inline name
      else
        name ||= 'Server error occured'
        name  += "\n\nkey: %s" % key

        Lux.error(name)
      end
    end
  end

  def render data
    %[<html><head><title>Server error (#{Lux.current.response.status})</title></head><body style="background:#fdd;"><pre style="color:red; padding:10px; font-size:14pt;">#{data.gsub('<','&lt;')}</pre></body></html>]
  end

  def show desc=nil
    ap [' Error: %s' % desc, caller]

    Lux.current.response.status 500
    data = "Lux #{Lux.current.response.status} error\n\n#{desc}"
    data = render(data) unless Lux.cli?
    Lux.current.response.body! data

    throw :done
  end

  def inline name=nil, o=nil
    o ||= $!

    dmp = [[], []]

    o.backtrace.each do |line|
      line = line.sub(Lux.root.to_s, '.')
      dmp[line.include?('/app/') ? 0 : 1].push line
    end

    dmp[0] = dmp[0].map { |_| _ = _.split(':', 3); '<b>%s</b> - %s - %s' % _ }

    name ||= 'Undefined name'
    msg    = $!.to_s.gsub('","',%[",\n "]).gsub('<','&lt;')

    %[<pre style="color:red; background:#eee; padding:10px; font-family:'Lucida Console'; line-height:15pt; font-size:11pt;"><b style="font-size:110%;">#{name}</b>\n\n<b>#{msg}</b>\n\n#{dmp[0].join("\n")}\n\n#{dmp[1].join("\n")}</pre>]
  end

  def log exp
    # Overload for custom log
    nil
  end
end
