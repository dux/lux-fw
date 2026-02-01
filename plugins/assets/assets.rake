# https://github.com/KaiHotz/react-rollup-boilerplate

require 'digest'

def import_css folder
  Dir.find(folder, ext: [:css, :scss], invert: true) { '@import "%s";' }
end

def import_js folder
  Dir.find(folder, ext: [:js, :coffee]) { 'import "%s";' }
end

def get_files folder, ext
  root = "./app/assets/auto/#{folder}/#{ext}"
  return [] unless Dir.exist?(root)
  files = Dir.find(root)
  files = files.reject { _1.include?('/!') }

  last_file = Dir.files(root).select { _1.include?('!last') }.first
  files.push "#{root}/#{last_file}" if last_file

  files = files.map do |f|
    if f =~ /\.rb$/
      data = instance_eval File.read f
      "/* #{f} */\n#{data}"
    else
      f
    end
  end

  files = files.map { _1.sub('./app/assets/', './') }

  files
end

namespace :assets do
  desc 'Auto assets compiler'
  task :auto do
    system "rm ./app/assets/auto-*"

    for folder in Dir.folders('./app/assets/auto')
      info = ["Auto asset compiler: #{folder}"]
      # JS FILES
      js_files = get_files folder, :js
      data = []
      for file in js_files
        if file.start_with?('/* ')
          data.push file
        else
          ext = file.split('.').last.to_sym
          if ext == :svelte
            name = file.split('/').last.split('.').first.gsub('-', '_')
            data.push <<~DATA
              import Svelte_#{name} from '#{file}';
              Svelte.bind('s-#{name.gsub('_', '-')}', Svelte_#{name});
            DATA
              .chomp
          elsif [:js, :coffee, :fez].include?(ext)
            data.push %[import "#{file}";]
          else
            raise "Unknown extension on #{file}"
          end
        end
      end

      if data[0]
        file = "./app/assets/auto-#{folder}.js"
        info.push file
        File.write(file, data.join("\n\n"))
      end

      # CSS fles
      css_files = get_files folder, :css
      data = []
      for file in css_files
        if file.start_with?('/* ')
          data.push file
        else
          code = code = 'sha1_' + Digest::SHA1.hexdigest(file)
          # data.push %[@use "#{file}" as #{code};]
          # data.push %[@use "#{file}";]
          data.push %[@use "#{file}" as *;]
          # data.push %[@import "#{file}";]
        end
      end

      if data[0]
        file = "./app/assets/auto-#{folder}.scss"
        info.push file
        File.write(file, data.join("\n\n"))
      end

      Lux.info info.join(' - ')
    end
  end
end
