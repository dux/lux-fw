class Object
  LUX_LOG_CLEAR_LAST ||= [0.0]

  # raise object
  def r what
    if what.is_a?(Method)
      rr [:source_location, what.source_location.join(':')]
    else
      rr what
    end

    what = what.respond_to?(:to_jsonp) ? what.to_jsonp : what.inspect
    raise StandardError.new(what.nil? ? 'nil' : what)
  end

  # shared dump style used by rr and LOG
  def raise_log_style what
    klass = what.class
    klass = '%s at %s' % [klass, what.source_location.join(':').sub(Lux.root.to_s, '.')] if klass == Method
    from = caller.find { |line| !line.include?('raise_variants.rb') } || caller[0]
    from = from.sub(Lux.root.to_s+'/', './').split(':in ').first
    header = '--- START (%s) %s - %s ---' % [klass, from, Lux.current.request.url]
    if ['Lux::Hash', 'Hash'].include?(what.class.to_s)
      $stderr.puts header
      $stderr.puts what.to_jsonp
      $stderr.puts '--- END ---'
    else
      # STDERR keeps rr/LOG on the same stream as Lux.log; STDOUT is redirected to /dev/null in dev
      $stderr.puts [header, what, '--- END ---'].ai
    end
  end

  # better console log dump - interactive debug helper, never call from
  # library code; if you see it in lib/ or plugins/, delete it.
  def rr what
    raise_log_style what
  end

  # tail -f ./log/LOG.log
  def LOG what
    from = caller[0].sub(Lux.root.to_s + '/', './').split(':in ').first

    if Lux.runtime.web?
      # silence other screen logs for the rest of this request
      Lux.current.var[:lux_disable_screen_log] = true
      unless Lux.current.var[:log_screen_cleared]
        Lux.current.var[:log_screen_cleared] = true
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        # throttle clear-screen to once per second across requests
        if now - LUX_LOG_CLEAR_LAST[0] >= 1.0
          LUX_LOG_CLEAR_LAST[0] = now
          $stderr.print "\e[H\e[2J"
        end
      end
      raise_log_style what
    end

    logger = Logger.new('./log/LOG.log')
    logger.formatter = proc do |severity, datetime, progname, msg|
      "#{Lux.app_caller} - #{from}\n#{msg}\n\n"
    end
    logger.info what.ai
  end

  # unique methods for object
  # includes methods from modules
  def r? object
    dump = []

    dump.push 'Class: %s' % object.class

    instance_unique = object.methods - object.class.ancestors[0].instance_methods
    class_unique    = object.methods

    object.class.ancestors.drop(1).each do |_|
      class_unique -= _.instance_methods

      if _.class != Module
        dump.push 'Parent Class: %s' % _
        break
      end
    end

    dump.push ['Instance uniqe', instance_unique.sort] if instance_unique[0]
    dump.push ['Uniqe from parent', class_unique.sort.join(', ')]
    dump.push ['Uniqe from parent simple', object.class.instance_methods(false)]

    rr dump
  end

  # dump all object methods, class or instance
  def m? object
    current = object.respond_to?(:ancestors) ? object : object.class
    parent = current.ancestors.select {_1.class == Class }[1]
    if object == current
      current.methods - parent.methods
    else
      object.methods - parent.instance_methods
    end
  end
end

###

# if we dont have awesome print in prodction, define mock
method(:ap) rescue Proc.new do
  class Object
    def ap(*args)
      puts args
    end
  end
end.call
