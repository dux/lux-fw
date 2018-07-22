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

      # generate cell assets
      if defined?(ViewCell)
        local  = '/assets/cell-assets.css'
        handle = Lux.root.join('public' + local)
        handle.write ViewCell.all_css
        puts 'Generated %s -> %s' % ['cell css assets'.green, local]
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
