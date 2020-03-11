Lux.config.error_logger = proc do |error|
  # log and show error page in a production
  key = SimpleException.log error
  Lux.cache.fetch('error-mail-%s' % key) { Mailer.error(error, key).deliver }
  Lux.logger(:exceptions).error [key, User.current.try(:email).or('guest'), error.message].join(' - ')
  key
end
