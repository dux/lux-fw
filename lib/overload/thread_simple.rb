# https://gist.github.com/dux/466507a5e86cadd2c4714381a1f06cf4

class Thread::Simple
  # Thread::Simple.run do |t|
  #   for foo in bar
  #     t.add { ... }
  #   end
  # end
  def self.run **args
    ts = new(**args)
    yield ts
    ts.run
    ts
  end

  # upload in 3 separate threads
  # Thread::Simple.each(data., size: 3) do |source, target|
  #   ::Cdn.cdn_upload "./public/assets/#{source}", "assets/#{target}"
  # end
  def self.each list, **args, &block
    ts = new(**args)
    list.send list.class == Hash ? :each : :each_with_index, &block
    ts.run
    ts
  end

  ###

  attr_accessor :que, :size

  def initialize size: 5, sleep: 0.05
    @sync     = Mutex.new
    @sleep    = sleep
    @size     = size
    @que      = []
    @threads  = []
    @name_val = {}
  end

  def add name = nil, &block
    @sync.synchronize do
      if name
        @que << proc do
          value = block.call
          @sync.synchronize { @name_val[name] = value }
        end
      else
        @que << block
      end
    end
  end

  def run endless: false
    @endless = endless

    @size.times do
      @threads << Thread.new do
        task = nil

        while active?
          @sync.synchronize { task = @que.pop }
          task.call if task
          sleep @sleep
        end
      end
    end

    unless @endless
      @threads.each(&:join)
    end
  end

  def stop
    @endless = false
  end

  def [] name
    @sync.synchronize { @name_val[name] }
  end

  # Read-only accessor for named results
  def named
    @sync.synchronize { @name_val.dup }
  end

  private

  def active?
    @endless || @sync.synchronize { !@que.empty? }
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
