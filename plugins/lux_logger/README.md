# Lux.plugin :lux_logger

Database-backed structured logger.

## Setup

```ruby
Lux.plugin :db
Lux.plugin :lux_logger
```

## Usage

```ruby
LuxLogger.log :user_login,   { ip: '1.2.3.4' }
LuxLogger.log :task_created, { task_ref: task.ref }
```

## Layout

```
plugins/lux_logger/
  loader.rb                  # requires lib/lux_logger
  lib/
    lux_logger.rb
```
