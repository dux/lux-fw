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

    ENV['RACK_ENV'] = 'production'

    assets = Dir['./app/assets/**/index.*'].map { |el| el.sub('./app/assets/','') }

    Lux.config.assets_precompile = true

    speed = Lux.speed do
      for file in assets
        assets = MiniAssets.new file

        puts "Generated #{file.green} -> #{assets.render}"
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
