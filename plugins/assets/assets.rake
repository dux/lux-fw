#!/usr/bin/env ruby

namespace :assets do
  desc 'Clear all assets'
  task :clear do
    run 'rm -rf ./tmp/assets'
    run 'rm -rf ./public/assets'
  end

  desc 'Compile assets to public/assets and generate mainifest.json'
  task :compile do
    require './config/application'

    assets  = Dir['./app/assets/**/index.*'].map { |el| el.sub('./app/assets/', '').sub(%r{/index\.\w+$}, '') }
    assets += Dir['./app/assets/**/assets'].map { |el| el.sub('./app/assets/', '').sub(%r{/assets$}, '') }

    assets.uniq!

    speed = Lux.speed do
      for file in assets
        dir = file.sub(/\/index\.\w+$/, '')

        assets = SimpleAssets.new dir

        puts "Generated #{file.green} -> #{assets.render}"
      end

      if defined?(ViewCell)
        for ext in [:css, :js]
          mname = 'all_%s' % ext
          fname = './public/assets/cell-assets.%s' % ext
          puts 'Generated ViewCell.%s -> %s' % [mname, fname]
          File.write(fname, ViewCell.send(mname))
        end
      end
    end

    puts "Asset precomlile done in #{speed}"
  end

  desc 'Upload assets to S3'
  task :s3_upload do
    die 's3://... location not provided' unless ARGV.last && ARGV.last[0,5] == 's3://'

    puts 'Copy to %s'.green % ARGV.last
    run 'aws s3 sync ./public %s --cache-control "max-age=31536000, public"' % ARGV.last
  end

end
