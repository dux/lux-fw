# https://github.com/wistia/nsq-ruby
# http://rustamagasanov.com/blog/2017/02/24/systemd-example-for-a-simple-ruby-daemon-supervision/

# lux e Nsq.read_test
# Nsq.write ok: 123
# Nsq.read { |msg| ap msg }

# how to use
# NSQ.define :cli { |data|  Lux.run data.cli }
# NSQ.write(:cli, { cli: 'curl ...' })
# NSQ.process

module Lux
  module DelayedJob
    module Nsq
      extend self

      TOPIC          ||= Lux.config[:que_topic]    || 'webapp'
      PRODUCER_SERVE ||= Lux.config[:nsq_producer] || '127.0.0.1:4150'
      CONSUMER_SERVE ||= Lux.config[:nsq_consumer] || '127.0.0.1:4161'

      def producer
        @producer ||= ::Nsq::Producer.new nsqd: PRODUCER_SERVE, topic: TOPIC
      end

      def consumer
        @consumer ||= ::Nsq::Consumer.new nsqlookupd: CONSUMER_SERVE, topic: TOPIC, channel: TOPIC
      end

      def write func, data
        producer.write [func, data].to_json
      end

      # generic read message interface
      def read
        while msg = consumer.pop
          begin
            data = JSON.parse msg.body
            yield data[0], data[1]
          rescue => error
            Lux::Error.split_backtrace error
          end

          msg.finish
        end
      end

      # process messages defined by define
      def process
        puts 'Bacground processor - %s' % self

        read do |func, data|
          Lux::DelayedJob.call func, data
        end
      end

      def start
        apps = [
          'cd tmp',
          'nsqlookupd &> nsqlookupd.log',
          'nsqd --lookupd-tcp-address=127.0.0.1:4160 --broadcast-address=localhost',
          'nsqadmin --lookupd-http-address=127.0.0.1:4161'
        ]

        command = "(trap 'kill 0' SIGINT; #{apps.join(' & ')})"

        Lux.run command
      end
    end
  end
end
