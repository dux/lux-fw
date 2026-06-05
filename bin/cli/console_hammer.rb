# Console-only helpers - defined on the real top-level Object so they're
# callable as bare commands at the pry prompt. Use ::Object.class_eval rather
# than `class Object`: this file is loaded through Hammer's string instance_eval
# (see hammer/builder.rb#evaluate), where a bare `class Object` resolves to the
# eval target's scope instead of ::Object, so the helpers never reach `main`.
::Object.class_eval do
  def cp data
    data = JSON.pretty_generate(data.to_hash) if data.respond_to?(:to_hash)
    Clipboard.copy data
    'copied'
  end

  def reload!
    Lux::Reloader.run :cli
  end

  def sql! sql=nil
    require 'niceql'
    puts Niceql::Prettifier.prettify_sql sql || Thread.current[:last_sql_command]
  end

  def c
    system('clear')
  end

  # m User, :secure_hash
  def m object, mtd = nil
    if mtd
      info = object.method(mtd)
      puts info.source_location.or([]).join(':').colorize(:yellow)
      puts '-'
      puts info.source
      nil
    else
      if object.respond_to?(:superclass)
        object.methods - object.superclass.methods
      else
        object.methods - object.class.superclass.methods
      end
    end
  end
end

task :console do
  desc 'Start console'
  alt :c
  needs :app

  proc do |opts|
    ENV['LUX_DEBUG']  ||= 'true'
    ENV['LUX_RELOAD'] ||= 'true'

    require 'pry'
    require 'amazing_print'

    # double Ctrl+C exits Pry: first one at an empty prompt arms the exit
    # and prints a hint, the next one bails out. Ctrl+C while typing only
    # cancels the buffer (Pry default) and disarms the exit.
    Pry::REPL.prepend(Module.new do
      def read
        val = super
        if val == :control_c
          if pry.eval_string.empty?
            if @_lux_ctrl_c_armed
              output.puts ''
              exit 0
            end
            @_lux_ctrl_c_armed = true
            output.puts '(press Ctrl+C again to exit)'
          else
            @_lux_ctrl_c_armed = false
          end
        else
          @_lux_ctrl_c_armed = false
        end
        val
      end
    end)

    # create mock session
    Lux::Current.new '/'

    if File.exist?('./config/console.rb')
      puts '* loading ./config/console.rb'
      require './config/console'
    else
      puts '* ./config/console.rb not found'
    end

    AmazingPrint.pry!
    Pry.pager = false

    # nice object dump in console
    Pry.config.print = proc do |output, data|
      puts data.class.to_s.colorize(:gray)

      out =
        if data.is_a?(Hash)
          JSON.pretty_generate(data).gsub(/"([\w\-]+)":/) { '"%s":' % $1.colorize(:yellow) }
        elsif data.is_a?(String)
          if data.downcase.start_with?('select')
            require 'niceql'
            Niceql::Prettifier.prettify_sql data
          else
            data
          end
        else
          data.ai
        end

      output.puts out unless data.nil?
    end

    args = opts[:args]
    if args.first
      command = args.join(' ')

      if command.end_with?('.rb')
        puts 'Load : %s' % command.colorize(:light_blue)
        load command
      else
        puts 'Command : %s' % command.colorize(:light_blue)
        data = eval command
        puts '-'
        Pry.config.print.call $stdout, data
      end
    else
      history = Pathname.new Lux.root.join('./.pry_history')

      Thread.new do
        sleep 0.5
        if history.exist?
          lines = history.read.split($/).uniq - ['exit']
          lines.each { |l| Pry.history.push(l) }
        end
      end
      Pry.start

      history.write Pry.history.to_a.uniq.last(100).join($/)
    end
  end
end
