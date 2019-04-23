require 'pry'

class Object
  def cp data
    data = JSON.pretty_generate(data.to_hash) if data.respond_to?(:to_hash)
    Clipboard.copy data
    'copied'
  end

  # show method info
  # show User, :secure_hash
  def show klass, m
    klass = klass.class unless klass.respond_to?(:new)
    el = klass.instance_method(m)
    puts el.source_location.or([]).join(':').yellow
    puts '-'
    puts el.source
    nil
  end
end

ARGV[0] = 'console' if ARGV[0] == 'c'

LuxCli.class_eval do
  desc :console, 'Start console'
  def console
    $lux_start_time = Time.now

    require 'awesome_print'
    require 'clipboard'
    require './config/application'

    Lux.config.dump_errors   = true
    Lux.config.log_to_stdout = true

    if File.exist?('./config/console.rb')
      puts '* loading ./config/console.rb'
      require './config/console'
    else
      puts '* ./config/console.rb not found'
    end

    # AwesomePrint.pry!
    # nice object dump in console
    Pry.print = proc { |output, data|
      out = if data.is_a?(Hash)
        data.class.to_s+"\n"+JSON.pretty_generate(data).gsub(/"(\w+)":/) { '"%s":' % $1.yellow }
      else
        data.ai
      end

      output.puts out
    }

    # create mock session
    Lux::Current.new '/'

    Pry.start
  end
end