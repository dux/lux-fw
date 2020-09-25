  class ErbParser
  def self.parse file
    new(file).parse_file
  end

  ###

  def initialize file
    @file = file
  end

  def import_css folder
    Dir.find(folder, ext: [:css, :scss]) { '@import "%s";' }
  end

  def import_js folder
    Dir.find(folder, ext: [:js, :coffee]) { 'import "%s";' }
  end

  def import folder
    @file.include?('.js.') ? import_js(folder) : import_css(folder)
  end

  def parse_file
    f = Pathname.new(@file)
    data = f.read

    Dir.chdir f.dirname.to_s do
      data = ERB.new(data).result(binding).gsub('././', './')
    end

    data
  end
end

###

LuxCli.class_eval do
  desc :erb, 'Parse and process *.erb templates'
  def erb file=nil
    # To create server side template, create file ending in .erb

    require './config/application'

    if file
      puts ErbParser.parse(file)
    else
      commmand = "find . -type file | grep --color=never \\.erb$"
      puts commmand.gray
      files = `#{commmand}`
        .split($/)
        .reject { |f| f.include?('/views/') }

      Cli.die 'No erb templates found' unless files.first

      for file in files
        target = file.sub(/\.erb$/, '')

        puts 'Assets compile: %s -> %s' % [file.green, target]
        out = []
        out.push "/* Generated from #{file} */"

        out.push ErbParser.parse(file)

        File.write(target, out.join("\n\n"))
      end
    end
  end
end
