class LuxStat
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
    mcnt = list.inject(0){ |t, m| t += m.instance_methods(false).length; t }

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

  def total
    dirs = Dir
      .entries('./app')
      .drop(2)
      .select { |it| File.directory?('./app/%s' % it) }

    max_len = dirs.max_by(&:length).length + 1

    for el in dirs
      files = `find ./app/#{el}/ -type f`.count($/)
      lines = `find ./app/#{el}/ -type f  | xargs wc -l`.split($/).last.to_i
      puts " #{files.pluralize(:files).rjust(9).white} and #{lines.pluralize(:lines).rjust(12).white} in #{el.blue}"
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
    stat.call :total, 'Totals per folder in ./app'
  end
end