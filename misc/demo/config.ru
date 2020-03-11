$lux_start_time = Time.now

require_relative 'config/application'

Lux.serve self
