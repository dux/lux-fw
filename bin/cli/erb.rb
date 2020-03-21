LuxCli.class_eval do
  desc :erb, 'Parse and process *.erb templates'
  def erb file=nil
    # To create server side template, create file ending in .erb

    require './config/application'

    if file
      out = File.read(file).parse_erb
      puts out
    else
      commmand = "find . -type file | grep --color=never \\.erb$"
      puts commmand.gray
      files = `#{commmand}`.split($/)

      Cli.die 'No erb templates found' unless files.first

      for file in files
        target = file.sub(/\.erb$/, '')

        puts 'Assets compile: %s -> %s' % [file.green, target]
        out = []
        out.push "/* Generated from #{file} */"
        out.push File.read(file).parse_erb

        File.write(target, out.join("\n\n"))
      end
    end
  end
end
