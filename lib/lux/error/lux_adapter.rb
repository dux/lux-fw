module Lux
  def error *args
    if args.first
      raise Lux::Error::AutoRaise.new(*args)
    else
      Lux::Error::AutoRaise
    end
  end
end
