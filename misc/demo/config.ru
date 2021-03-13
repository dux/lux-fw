$lux_start_time = Time.now

require_relative 'config/app'

Lux.serve self
