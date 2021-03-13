# http://contribsys.com/faktory/
# https://github.com/contribsys/faktory
# https://github.com/contribsys/faktory_worker_ruby
# http://localhost:7420/ - admin interface

if defined?(Factory)
  class FaktoryJobWorker
    include Faktory::Job

    def perform func, data
      Lux::DelayedJob.call func, data
    end
  end
end

module Lux
  module DelayedJob
    module Faktory
      extend self

      def write func, data
        FaktoryJobWorker.perform_async func, data
      end

      def read
      end

      def process
        system 'bundle exec faktory-worker -r ./config/app.rb'
      end

      def start
        Lux.run 'faktory'
      end
    end
  end
end
