# @object.whatever :some_param
# @object.delay.whatever :some_param

class Lux::DelayedJob::ObjectProxy
  def initialize object
    @object = object
  end

  def method_missing name, *args
    @method = name
    dump = Marshal.dump [@object, name, args]
    dump = Base64.urlsafe_encode64 dump
    Lux.delay :__object_message, dump
    true
  end
end

class Object
  def delay
    Lux::DelayedJob::ObjectProxy.new self
  end
end

# run command on cli
Lux.delay.define :__object_message do |data|
  unpacked = Base64.urlsafe_decode64 data
  unpacked = Marshal.load unpacked
  object, m, args = *unpacked

  Lux.log do
    arguments = args.present? ? args.to_json : ''
    ' Delayed job execute: @%s.%s(%s)'.cyan % [object.class.to_s.tableize.singularize, m, arguments]
  end

  object.send(m, *args)

  true
end

