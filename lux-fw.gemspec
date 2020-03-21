# http://stackoverflow.com/questions/5159607/rails-engine-gems-dependencies-how-to-load-them-into-the-application

gem_files = [:bin, :lib, :plugins, :tasks]
  .inject([]) { |t, el| t + `find ./#{el}`.split($/) }
  .push './.version'

Gem::Specification.new 'lux-fw' do |gem|
  gem.version     = File.read('.version')
  gem.summary     = 'Lux - the ruby framework'
  gem.description = 'Ruby framework optimized for speed and linghtness'
  gem.homepage    = 'http://github.com/dux/lux-fw'
  gem.license     = 'MIT'
  gem.author      = 'Dino Reic'
  gem.email       = 'rejotl@gmail.com'
  gem.files       = gem_files

  gem.executables = ['lux']

  # added by analogy
  gem.add_dependency 'rack'

  # we need json from gem
  gem.add_dependency 'json'

  # session encryption
  gem.add_dependency 'jwt'

  # 5.minutes
  gem.add_dependency 'as-duration'

  # various type systems and schemas
  gem.add_dependency 'typero'

  # html string building lib
  gem.add_dependency 'html-tag'

  # class and method attributes, rescue_from
  gem.add_dependency 'clean-annotations'

  # hash inifferent access, hash to struct
  gem.add_dependency 'clean-hash'

  # mail sending ruby gold
  gem.add_dependency 'mail'

  # rake tasks
  gem.add_dependency 'rake'

  # used for "bundle exec lux"
  gem.add_dependency 'thor'

  # for console
  gem.add_dependency 'pry'

  # sweet cli spinner
  gem.add_dependency 'whirly'

  # formated SQL debugging
  gem.add_dependency 'niceql'

  ### possible removal in the future

  # better errors in developmet
  gem.add_dependency 'better_errors'

  # ruby web server for development
  gem.add_dependency 'puma'

  # load .env if present
  gem.add_dependency 'dotenv'

  # best ORM mapper for ruby/postgres
  gem.add_dependency 'sequel_pg'

  # nice colorized output
  gem.add_dependency 'colorize'

  # because it is awesome
  gem.add_dependency 'awesome_print'

  # best server side templateing
  gem.add_dependency 'hamlit'
  gem.add_dependency 'hamlit-block'

  # better development errors
  # gem.add_dependency 'binding_of_caller'

  # gem.add_dependency 'dry-inflector'
  # gem.add_dependency 'nokogiri'
end