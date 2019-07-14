# how to use
# Lux.job.server = :nsq
# Lux.job.define :cli { |data|  Lux.run data }
# Lux.job.cli 'curl ...'
# Lux.job.add 'cli', 'curl ...'
# Lux.job.add 'cli#not/defined', 'curl ...' # error
# Lux.job.process

module Lux::DelayedJob
  extend self

  WORKER = {}

  def server= name
    @server = name.is_a?(Symbol) ? "Lux::DelayedJob::#{name.to_s.capitalize}".constantize : name
  end

  def server
    @server
  end

  def define name, &block
    METHODS[name] = block
  end

  def call name, *args
    m = METHODS[name]
    raise ArgumentError.new('Method %s not defined' % name) unless m
    METHODS[name].call *args
  end

  def push name, *args
    args.first ||= nil
    @server.push name, args.to_json
  end

  # attr_reader :server

  # @server = :memory

  # def server= name
  #   adapter =
  #   @server = adapter.constantize
  # rescue NameError
  #   die 'No adapter %s not found' % adapter
  # end

  # def add object, method_to_call=nil
  #   die "No DelayedJob server defined" unless @server
  #   @server.push [object, method_to_call]
  # end

  # def process
  #   obj, method_to_call = @server.pop

  #   return unless obj

  #   puts "JOB POP> #{obj.to_s}.#{method_to_call}".yellow

  #   if method_to_call
  #     begin
  #       obj.send(method_to_call)
  #     rescue
  #       puts("Lux::DelayedJob.pop FAIL for :#{method_to_call} (#{$!.message})".red)
  #     end
  #   else
  #     eval(obj)
  #   end

  #   true
  # end

  # def run! seconds=1
  #   puts "JOB QUE> is running for #{@server}".green

  #   Thread.new do
  #     while true
  #       print '.'
  #       true while Lux::DelayedJob.pop
  #       sleep seconds
  #     end
  #   end.join
  # end
end
