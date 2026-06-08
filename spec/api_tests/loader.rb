ENV['LUX_ENV'] = 'test'

require 'test_helper'
require_relative './lib/blank'

# Test fixture API classes - shared across every api_tests/tests/*_spec.rb
require_relative './api/application_api'
require_relative './api/generic_api'
require_relative './api/model_api'
require_relative './api/company_api'
require_relative './api/user_api'
require_relative './api/models'
require_relative './api/todo_models'
require_relative './api/board_api'
