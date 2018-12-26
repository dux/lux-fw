# https://gist.github.com/dux/466507a5e86cadd2c4714381a1f06cf4

class Thread::Simple
  def initialize max_threads=10
    @pool = SizedQueue.new max_threads
    max_threads.times { @pool << 1 }
    @mutex   = Mutex.new
    @threads = []
    @list    = []
    @named   = {}
  end

  def add name=nil
    @pool.pop
    @mutex.synchronize do
      @threads << Thread.start do
        begin
          @named[name] = yield name
        rescue Exception => e
          puts "Exception: #{e.message}\n#{e.backtrace}"
        ensure
          @pool << 1
        end
      end
    end
  end

  def run
    @threads.each &:join
  end

  def [] name
    @named[name]
  end
end
