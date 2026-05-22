module Lux
module Utils
module TimeOptions
  def short use_default = false
    # lang = Lux.current.request.env['HTTP_ACCEPT_LANGUAGE'] rescue 'en'
    default_format = '%Y-%m-%d'
    date_format    = Lux.current.var[:date_format].or(Lux.config[:date_format] || default_format)
    date_format    = default_format if use_default
    date_format    = date_format.sub('yyyy', '%Y').sub('mm', '%m').sub('dd', '%d')

    current.strftime date_format
  end

  def long use_default=false
    current.strftime("#{short(use_default)} %H:%M")
  end

  def current
    if respond_to?(:utc) && time_zone = Lux.current.var[:time_zone]
      begin
        tz = TZInfo::Timezone.get(time_zone)
        tz.utc_to_local utc
      rescue TZInfo::InvalidTimezoneIdentifier => e
        Lux.logger.error '%s (%s)' % [e.message, time_zone]
        self
      end
    else
      self
    end
  end
end
end
end
