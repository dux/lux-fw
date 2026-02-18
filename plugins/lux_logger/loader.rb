# LuxLogger - Database-backed structured logger
#
# Usage:
#   LuxLogger.log :user_login, { ip: '1.2.3.4' }
#   LuxLogger.log :task_created, { task_ref: task.ref }

require_relative 'lib/lux_logger'
