# https://github.com/KaiHotz/react-rollup-boilerplate

require 'digest'

namespace :assets do
  desc 'Generate Procfile data. You can run it with overmind or foreman'
  task :run do
    files = []
    files.push 'js: rollup -cw'

    for file in Dir.files('./app/assets').filter { |_| %w(css sass scss).include?(_.split('.').last) }
      files.push "#{file.gsub('.', '_')}: find app/assets -name *.*css | entr -r npx node-sass app/assets/#{file} -o public/assets/ --output-style expanded --source-comments"
    end

    puts files.join($/)
  end

  desc 'Build and generate manifest'
  task :compile do
    Lux.run 'rm -rf public/assets'
    Lux.run 'rollup -c --compact'

    for css in Dir.files('app/assets').select { |it| it.ends_with?('.css') }
      Lux.run "npx node-sass app/assets/#{css} -o public/assets/ --output-style compressed"
    end

    integrity = 'sha512'
    files     = Dir.entries('./public/assets').drop(2)
    manifest  = Pathname.new('./public/manifestx.json')
    json      = { integrity: {}, files: {} }

    for file in files
      local     = './public/assets/' + file
      sha1      = Digest::SHA1.hexdigest(File.read(local))[0,12]
      sha1_path = file.sub('.', '.%s.' % sha1)

      json[:integrity][file] = '%s-%s' % [integrity, `openssl dgst -#{integrity} -binary #{local} | openssl base64 -A`.chomp]
      json[:files][file] = sha1_path

      Lux.run "cp #{local} ./public/assets/#{sha1_path}"
    end

    manifest.write JSON.pretty_generate(json)

    Lux.run "gzip -9 -k public/assets/*.*"
    Lux.run 'ls -lSrh public/assets | grep .gz --color=never'
  end

  desc 'Install example rollup.config.js, package.json and Procfile'
  task :install do
    src = Lux.fw_root.join('plugins/assets/root')

    for file in Dir.files(src)
      target = Lux.root.join(file)

      print file.ljust(18)

      if target.exist?
        puts ' - exists'
      else
        Lux.run "cp %s %s" % [src.join(file), target]
        puts '-> copied'.green
      end
    end

    puts
    Lux.run 'cat %s' % src.join('Procfile')
  end
end
