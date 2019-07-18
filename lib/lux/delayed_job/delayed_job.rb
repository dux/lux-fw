# how to use
# Lux.delay.server = :nsq
# Lux.delay.define :cli { |data| Lux.run data }
# Lux.delay :cli, 'curl ...'
# Lux.delay.push 'cli#not/defined', 'curl ...' # error
# Lux.delay.process
# run command on cli

module Lux::DelayedJob
  extend self

  METHODS = {}

  def server= name
    @server = name.is_a?(Symbol) ? "Lux::DelayedJob::#{name.to_s.capitalize}".constantize : name
    [:write, :read, :process].each { |m| Lux.die(':%s method not found in %s task server' % [m, @server]) unless @server.respond_to?(m) }
  end

  def server
    raise ArgumentError.new('server not defined') unless @server
    @server
  end

  def define name, &block
    METHODS[name.to_s] = block
  end

  def process
    @server.process
  end

  def write func, data=nil
    Lux.logger(:background_job_write).info [func, data].join(': ')
    @server.write func.to_s, data
  end

  def call func, msg
    Lux.log { 'Bacrground job "%s": %s' % [func, msg] }

    if m = METHODS[func]
      Thread.new do
        begin
          Timeout::timeout(10) do
            msg = msg.h if msg.is_a?(Hash)
            m.call msg
          end
        rescue => e
          error = "#{e.class}: #{e.message} (:#{func}, #{msg})"
          Lux.log "background job error: #{error}"
          Lux.logger('background-job-errors').error error
        end
      end
    else
      Lux.log 'Error: nsq method "%s" not defined'.red % func
    end
  end
end
