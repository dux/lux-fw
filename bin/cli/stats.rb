class LuxStat
  attr_accessor :dir

  def call name, title=nil
    puts (title || name.to_s.capitalize).yellow
    send name
    puts
  end

  def controllers
    list_method_classes Lux::Controller
  end

  def cells
    list_method_classes ViewCell
  end

  def models
    list = ObjectSpace
      .each_object(Class)
      .select{ |it| it.ancestors.include?(ApplicationModel) }
      .map(&:to_s)
      .sort
      .drop(1)
      .map(&:constantize)

    desc = list.length.pluralize(:models)
    mcnt = list.inject(0){ |t, m| t + m.instance_methods(false).length }

    list = list.map(&:to_s)

    while data = get_line(list, 100)
      puts ' ' + data
    end

    puts " #{desc} and #{mcnt.pluralize(:method)}".blue
  end

  def views
    view_dirs = Dir
      .entries('./app/views')
      .drop(2)
      .select { |it| File.directory?('./app/views/%s' % it) }

    for dir in view_dirs
      files = `find app/views/#{dir}/ -type f`.count($/)
      puts " #{files.pluralize(:file).rjust(9).white} in #{dir.blue}"

    end
  end

  def total_ext
    exts = {}
    excluding = %w(.git tmp .gems vendor node_modules log).sort
    puts '  Excluding: %s' % excluding.join(', ')
    puts '  To find: find . -type file | grep \\\\.ext$'
    puts

    files = `find . -type file | grep -v #{excluding.map{|el| " -e './#{el}/'" }.join(' ')}`.split($/)
    for file in files
      ext = file.split('.').last
      next if ext.length > 6
      exts[ext] ||= [0, 0]
      exts[ext][0] += 1
      exts[ext][1] += (File.read(file).split($/).length rescue 0)
    end

    for ext, (files, lines) in exts.sort
      next if lines == 0
      next if %w(conf app webloc ru xml edit json lock rake svg txt yaml yml).include?(ext)
      puts "#{ext.to_s.rjust(8).white} #{lines.pluralize(:line).rjust(14)} in #{files.pluralize(:files).white}"
    end
  end

  private


  def get_line list, len
    data = list.shift || return

    while data.length < len
      el = list.shift
      return data unless el
      data += ', %s' % el
    end

    data
  end

  def list_method_classes name
    classes = ObjectSpace
      .each_object(Class)
      .select{ |it| it.ancestors.include?(name) }
      .reject{ |it| it == name }
      .map(&:to_s)
      .reject{ |it| it[0,1]=='#' }
      .sort
      .map(&:constantize)

    max = classes.inject(0) { |t, it| t = it.to_s.length if it.to_s.length > t; t }
    n_methods = 0

    for klass in classes
      list = klass.instance_methods(false).map(&:to_s)
      next unless list.first

      n_methods += list.length

      prefix = ' ' + klass.to_s.ljust(max + 2).white

      while data = get_line(list, 100 - max)
        print prefix
        puts data
        prefix = ' ' * max + '   '
      end
    end

    puts " #{n_methods.pluralize('method')} in #{classes.length.pluralize('classes')}".blue
  end
end

LuxCli.class_eval do
  desc :stats, 'Print project stats'
  def stats
    require './config/application'

    stat = LuxStat.new
    stat.call :controllers
    stat.call :cells if defined?(ViewCell)
    stat.call :models
    stat.call :views

    for dir in %w[./]
      next unless Dir.exist?(dir)
      stat.dir = dir
      stat.call :total_ext, 'Totals per file type in %s' % dir
    end
  end
end