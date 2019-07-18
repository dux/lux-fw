# @object.delay.whatever

class Lux::DelayedJob::ObjectProxy
  def initialize object
    @object = object
    @dump   = Base64.urlsafe_encode64 Marshal.dump object
  end

  def method_missing name, *args
    @method = name
    ap [@object.class.to_s, name.to_s, args, @dump]
    true
  end
end

class Object
  def delay
    Lux::DelayedJob::ObjectProxy.new self
  end
end