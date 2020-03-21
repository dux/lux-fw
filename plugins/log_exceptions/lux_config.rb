Lux.config.error_logger = proc do |error|
  # log and show error page in a production
  key = SimpleException.log error

  if !File.exists?('./log/exceptions/%s.txt' % key) && Lux.env.prod?
    Mailer.error(error, key).deliver
  end

  Lux.logger(:exceptions).error [key, User.current.try(:email).or('guest'), error.message].join(' - ')

  key
end
