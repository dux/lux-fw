source 'http://rubygems.org'

gemspec

# Use the adjacent local checkout when present (developer convenience).
gem 'lux-hammer', path: '../lux-hammer' if File.directory?(File.expand_path('../lux-hammer', __dir__))

gem 'minitest'
gem 'rspec' # plugin specs under plugins/**/spec use expect/double style; see spec/spec_helper.rb
gem 'sqlite3'

# faker drives sample data inside mocks; clean-mock is vendored under
# Lux::Test::CleanMock so the gem dep is no longer required.
gem 'faker'
