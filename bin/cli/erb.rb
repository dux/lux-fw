LuxCli.class_eval do
  desc :erb, 'Parse and process *.erb templates'
  def erb file=nil
    # To create server side template, create file ending in .erb

    require './config/application'

    if file
      puts AssetGenerator.parse_template file
    else
      commmand = "find . -type file | grep --color=never \\.erb$"
      puts commmand.gray
      files = `#{commmand}`.split($/)

      Cli.die 'No erb templates found' unless files.first

      for file in files
        AssetGenerator.parse_template file
      end
    end
  end
end
