require 'fileutils'
require 'sequel'
require 'pp'

Sequel.extension :inflector

module LuxGenerate
  extend self

  def generate object=nil, objects=nil
    Cli.die "./generate [object singular]" unless object

    template_dir = 'config/templates'
    Cli.die "Lux::View dir #{template_dir} is not accessible" unless Dir.exists?(template_dir)

    tpl_desc = {
      p:'api',
      m:'model',
      a:'admin',
      c:'controller',
      v:'view'
    }

    @object  = object
    @objects = objects || @object.pluralize

    puts "Singular  : #{@object.yellow}"
    puts "Plural    : #{@objects.yellow}"

    def parse_vars(data)
      object  = @object
      objects = @objects
      klass   = @object.classify

      data.gsub(/\{\{([^\}]+)\}\}/) { eval $1 }
    end

    # get all files
    templates = {}
    for el in Dir["./#{template_dir}/*.*"].map{ |file| file.split('/').last }
      begin
        data = parse_vars(File.read("#{template_dir}/#{el}"))
      rescue
        puts '-'
        puts "File error: #{el.red}: #{$!.message}"
        exit
      end
      type = el[0,1]

      path = el.split('|', 2)[1]
      path = parse_vars(path).gsub('#','/')

      templates[type] ||= []
      templates[type].push [path, data]
    end

    # # puts  "Lux::Views : #{templates.keys.sort.map{ |el| tpl_desc[el.to_sym] ? tpl_desc[el.to_sym].sub(el, el.upcase.yellow) : el.yellow }.join(', ')}"
    puts  "Lux::Views : #{templates.keys.map{ |el| "#{tpl_desc[el.to_sym]}(#{el.yellow})" }.join(', ')}"
    print "Execute   : "

    parse_templates = STDIN.gets.chomp

    for type in templates.keys
      next unless parse_templates.index(type)
      for el in templates[type]
        file, data = *el
        if File.exists?(file)
          print 'exists'.yellow.rjust(20)
        else
          FileUtils.mkdir_p(file.sub(/\/[^\/]+$/,'')) rescue false
          File.open(file, 'w') { |f| f.write(data) }
          print 'created'.green.rjust(20)
        end
        puts ": #{file}"
      end
    end
  end
end

LuxCli.class_eval do
  desc :generate, 'Genrate models, cells, ...'
  def generate object, objects=nil
    LuxGenerate.generate object, objects
  end
end