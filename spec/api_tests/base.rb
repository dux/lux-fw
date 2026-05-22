require 'rubygems'
require 'bundler'

Bundler.require :dev

require_relative './lib/blank'
require_relative '../../../lib/lux-fw'

# Test fixture API classes
require_relative './api/application_api'
require_relative './api/generic_api'
require_relative './api/model_api'
require_relative './api/company_api'
require_relative './api/user_api'

require_relative './api/models.rb'
require_relative './api/todo_models'
require_relative './api/board_api'

class Object
  def pp data
    puts
    if data.is_a?(Hash)
      puts JSON.pretty_generate(data)
    else
      puts data.inspect
    end
  end

  def rr data
    return if ENV['RACK_ENV'] == 'test'
    puts '- start: %s - %s' % [data.class, caller[0].sub(__dir__+'/', '')]
    puts data.inspect
    puts '- end'
  end
end
