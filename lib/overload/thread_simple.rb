# https://gist.github.com/dux/466507a5e86cadd2c4714381a1f06cf4

class Thread::Simple
  STOP ||= :__stop__

  # Thread::Simple.run do |t|
  #   for foo in bar
  #     t.add { ... }
  #   end
  # end
  def self.run(**args)
    ts = new(**args)
    yield ts
    ts.run
    ts
  end

  # run block for each item in parallel
  # Thread::Simple.each(files, size: 3) do |file|
  #   upload(file)
  # end
  def self.each(list, **args, &block)
    ts = new(**args)
    if list.is_a?(Hash)
      list.each { |k, v| ts.add { block.call(k, v) } }
    else
      list.each { |item| ts.add { block.call(item) } }
    end
    ts.run
    ts
  end

  ###

  attr_reader :size

  def initialize(size: 5)
    @size     = size
    @queue    = Thread::Queue.new
    @threads  = []
    @mutex    = Mutex.new
    @name_val = {}
  end

  def add(name = nil, &block)
    if name
      @queue << proc do
        value = block.call
        @mutex.synchronize { @name_val[name] = value }
      end
    else
      @queue << block
    end
  end

  def run(endless: false)
    @endless = endless

    @size.times do
      @threads << Thread.new do
        while (task = @queue.pop) != STOP
          task.call
        end
      end
    end

    unless @endless
      # signal each worker to stop, then wait
      @size.times { @queue << STOP }
      @threads.each(&:join)
    end
  end

  def stop
    @size.times { @queue << STOP }
    @threads.each(&:join)
  end

  def [](name)
    @mutex.synchronize { @name_val[name] }
  end

  def named
    @mutex.synchronize { @name_val.dup }
  end
end
