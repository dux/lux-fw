# http://stackoverflow.com/questions/5159607/rails-engine-gems-dependencies-how-to-load-them-into-the-application

gem_files = [:bin, :lib, :plugins, :tasks]
  .inject([]) { |t, el| t + `find ./#{el}`.split($/) }
  .push './.version'

Gem::Specification.new 'lux-fw' do |gem|
  gem.version     = File.read('.version')
  gem.summary     = 'Lux - the ruby framework'
  gem.description = 'Ruby framework optimized for speed and linghtness'
  gem.homepage    = 'http://trifolium.hr/lux'
  gem.license     = 'MIT'
  gem.author      = 'Dino Reic'
  gem.email       = 'rejotl@gmail.com'
  gem.files       = gem_files

  gem.executables = ['lux']

  gem.add_runtime_dependency 'awesome_print', '~> 1'
  gem.add_runtime_dependency 'as-duration', '~> 0'
  gem.add_runtime_dependency 'colorize', '~> 0'
  gem.add_runtime_dependency 'jwt', '~> 1'
  gem.add_runtime_dependency 'hamlit', '2.9.5'
  gem.add_runtime_dependency 'hamlit-block', '~> 0'
  gem.add_runtime_dependency 'hashie', '~> 3'
  gem.add_runtime_dependency 'rack', '~> 2'
  gem.add_runtime_dependency 'sequel_pg', '~> 1'
  gem.add_runtime_dependency 'typero', '~> 0'
  gem.add_runtime_dependency 'dotenv', '~> 2'
  gem.add_runtime_dependency 'html-tag', '~> 1'
  # gem.add_runtime_dependency 'dry-inflector', '~> 0'

  gem.add_dependency 'mail', '~> 2'
  gem.add_dependency 'rake', '~> 12'
  gem.add_dependency 'thor', '~> 0'
  gem.add_dependency 'clipboard', '~> 1'
  gem.add_dependency 'pry', '~> 0'
  gem.add_dependency 'puma', '~> 3'
  gem.add_dependency 'better_errors', '~> 2'
  gem.add_dependency 'binding_of_caller', '~> 0'
  gem.add_dependency 'nokogiri', '~> 1'
  gem.add_dependency 'whirly', '~> 0'
  gem.add_dependency 'pry-coolline', '~> 0'
  gem.add_dependency 'niceql', '~> 0'
end