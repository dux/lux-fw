module Lux
  # BACKGROUND_THREADS ||= []
  # Kernel.at_exit { BACKGROUND_THREADS.each { |t| t.join } }

  # if block given, simple new thread bg job
  #   Lux.delay(self) { |object| ... }
  # if string given, write it to a job server
  #   Lux.delay(mail_object, :deliver)
  # without params return module
  #   Lux.delay
  def delay *args
    if block_given?
      lux_env = current
      t = Thread.new do
        begin
          Thread.current[:lux] = lux_env
          Timeout::timeout(Lux.config.delay_timeout) do
            yield *args
          end
        rescue => e
          if Lux.config.log_to_stdout
            ap ['Lux.delay error', e.message, e.backtrace]
          else
            Lux.logger(:delay_errors).error [e.message, e.backtrace]
          end
        end
      end

      # BACKGROUND_THREADS.push t
    elsif args[0]
      # Lux.delay(mail_object, :deliver)
      Lux::DelayedJob.write *args
    else
      Lux::DelayedJob
    end
  end
end