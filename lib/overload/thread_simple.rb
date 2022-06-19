# https://gist.github.com/dux/466507a5e86cadd2c4714381a1f06cf4

class Thread::Simple
  attr_accessor :que, :size, :named

  def initialize size: 5, sleep: 0.05
    @sync     = Mutex.new
    @sleep    = sleep
    @size     = size
    @que      = []
    @threds   = []
    @name_val = {}
  end

  def add name = nil, &block
    @sync.synchronize do
      if name
        @que << proc { @name_val[name] = block.call }
      else
        @que << block
      end
    end
  end

  def run endless: false
    @endless = endless

    @size.times do
      @threds << Thread.new do
        task = nil

        while active?
          @sync.synchronize { task = @que.pop }
          task.call if task
          sleep @sleep
        end
      end
    end

    unless @endless
      @threds.each(&:join)
    end
  end

  def stop
    @endless = false
  end

  def [] name
    @name_val[name]
  end

  private

  def active?
    @endless || @que.first
  end
end

###

# pool = Thread::Simple.new

# 1.upto(20) do |i|
#   pool.add i do
#     print '.'
#     time = rand
#     sleep time
#     'Integer: %s (%s - %s)' % [i, pool.que.size, time]
#   end
# end

# Thread.new do
#   sleep 5
#   pool.stop
# end

# pool.run endless: true

# puts

# for key in pool.named.keys.sort
#   puts '%s -> %s' % [key, pool.named[key]]
# end

# puts
# puts pool[10]
