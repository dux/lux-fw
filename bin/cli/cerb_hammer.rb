class ErbParser
  def self.parse file
    new(file).parse_file
  end

  def initialize file
    @file = file
  end

  def import_css folder
    Dir.find(folder, ext: [:css, :scss], invert: true) { '@import "%s";' }
  end

  def import_js folder
    Dir.find(folder, ext: [:js, :coffee]) { 'import "%s";' }
  end

  def import_svelte folder:, prefix:
    out = []
    out.push ''

    for file in Dir.find(folder, ext: [:svelte])
      name = file.split('/').last.split('.').first.downcase
      klass = "Svelte_#{prefix}_#{name}".gsub(/[^\w]/, '_')

      out.push "import #{klass} from './#{file}';"
      out.push "Svelte.bind('#{prefix}-#{name.gsub('_', '-')}', #{klass});"
      out.push ''
    end

    out.join($/)
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

define :cerb do
  desc 'Parse and process *.cerb templates (cli erb)'
  needs :app

  proc do |opts|
    file = opts[:args].first

    if file
      puts ErbParser.parse(file)
    else
      command = 'find . -type file | grep --color=never \.cerb$'
      puts command.colorize(:gray)
      files = `#{command}`
        .split($/)
        .reject { |f| f.include?('/views/') }

      error 'No erb templates found' unless files.first

      for local in files
        next if local.include?('/.')

        target = local.sub(/\.cerb$/, '')

        out = []
        out.push "/* Generated from #{local} */"
        out.push ErbParser.parse(local)
        File.write(target, out.join("\n\n"))

        puts 'Assets compile: %s -> %s (%s)' % [local.colorize(:green), target, File.size(target).to_filesize]
      end
    end
  end
end
