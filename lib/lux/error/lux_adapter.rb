module Lux
  def error *args
    if args.first
      raise Lux::Error.new(*args)
    else
      Lux::Error
    end
  end
end
