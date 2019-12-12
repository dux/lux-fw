# Thread safe hash

class MutexHash
  @@data ||= {}
  @@mutex  = Mutex.new

  def initialize name=nil
    @namespace = name || :_default
    @@mutex.synchronize do
      @@data[@namespace] ||= {}
    end
  end

  def [] name
    @@data[@namespace][name]
  end

  def []= name, value
    @@mutex.synchronize do
      @@data[@namespace][name] = value
    end
  end

  def method_missing name, *args
    MutexHash.new name
  end
end