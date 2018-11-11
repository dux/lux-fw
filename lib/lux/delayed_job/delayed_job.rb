module Lux::DelayedJob
  extend self

  attr_reader :server

  def server= name
    adapter = "Lux::DelayedJob::#{name.to_s.capitalize}"
    @server = adapter.constantize
  rescue NameError
    die 'No adapter %s not found' % adapter
  end

  def push object, method_to_call=nil
    die "No DelayedJob server defined" unless @server
    @server.push [object, method_to_call]
  end

  def pop
    obj, method_to_call = @server.pop

    return unless obj

    puts "JOB POP> #{obj.to_s}.#{method_to_call}".yellow

    if method_to_call
      begin
        obj.send(method_to_call)
      rescue
        puts("Lux::DelayedJob.pop FAIL for :#{method_to_call} (#{$!.message})".red)
      end
    else
      eval(obj)
    end

    true
  end

  def run! seconds=1
    puts "JOB QUE> is running for #{@server}".green

    Thread.new do
      while true
        print '.'
        true while Lux::DelayedJob.pop
        sleep seconds
      end
    end.join
  end
end
