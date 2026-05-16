require 'fileutils'
require 'sequel'
require 'pp'

Sequel.extension :inflector

module LuxGenerate
  module_function

  def generate object=nil, objects=nil
    raise Hammer::Error, './generate [object singular]' unless object

    template_dir = 'config/templates'
    raise Hammer::Error, "Lux::Template dir #{template_dir} is not accessible" unless Dir.exist?(template_dir)

    tpl_desc = {
      p: 'api',
      m: 'model',
      a: 'admin',
      c: 'controller',
      v: 'view'
    }

    @object  = object
    @objects = objects || @object.pluralize

    puts "Singular  : #{@object.colorize(:yellow)}"
    puts "Plural    : #{@objects.colorize(:yellow)}"

    def parse_vars(data)
      object  = @object
      objects = @objects
      klass   = @object.classify
      klasses = klass.pluralize

      data.gsub(/\{\{([^\}]+)\}\}/) { eval $1 }
    end

    templates = {}
    for el in Dir["./#{template_dir}/*.*"].map { |file| file.split('/').last }
      begin
        data = parse_vars(File.read("#{template_dir}/#{el}"))
      rescue
        puts '-'
        puts "File error: #{el.colorize(:red)}: #{$!.message}"
        exit
      end
      type = el[0, 1]

      path = el.split('|', 2)[1]
      path = parse_vars(path).gsub('#', '/')

      templates[type] ||= []
      templates[type].push [path, data]
    end

    puts  "Templates : #{templates.keys.map { |el| "#{tpl_desc[el.to_sym]}(#{el.colorize(:yellow)})" }.join(', ')}"
    print "Execute   : "

    parse_templates = STDIN.gets.chomp

    for type in templates.keys
      next unless parse_templates.index(type)
      for el in templates[type]
        file, data = *el
        if File.exist?(file)
          print 'exists'.colorize(:yellow).rjust(20)
        else
          FileUtils.mkdir_p(file.sub(/\/[^\/]+$/, '')) rescue false
          File.open(file, 'w') { |f| f.write(data) }
          print 'created'.colorize(:green).rjust(20)
        end
        puts "  #{file}"
      end
    end
  end
end

define :generate do
  desc 'Generate models, cells, ...'

  proc do |opts|
    object, objects = opts[:args]
    LuxGenerate.generate object, objects
  end
end
