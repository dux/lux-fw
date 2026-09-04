source 'http://rubygems.org'

gemspec

# Use the adjacent local checkout when present (developer convenience).
gem 'lux-hammer', path: '../lux-hammer' if File.directory?(File.expand_path('../lux-hammer', __dir__))

gem 'minitest'
gem 'sqlite3'

# plugin specs under plugins/**/spec use expect/double style; see spec/spec_helper.rb.
# Kept out of the default group: both helpers call Bundler.require, and rspec's
# expose_dsl_globally overrides Kernel#describe, which silently swallows every
# minitest spec in the process. The rspec runner loads rspec-core itself.
gem 'rspec', group: :rspec

# faker drives sample data inside mocks; clean-mock is vendored under
# Lux::Test::CleanMock so the gem dep is no longer required.
gem 'faker'
