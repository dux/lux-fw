# called by "lux secrets" cli tool

require 'yaml'

module Lux
  class Secrets
    attr_reader :read_file, :secret_file, :secret, :strength

    def initialize
      @tmp_file    = Pathname.new './tmp/secrets.yaml'
      @secret_file = Pathname.new './config/secrets.enc'
      @common_file = Pathname.new './config/secrets.yaml'
      @secret      = Lux.config[:secret_key_base] || Lux.config[:secret] || ENV['SECRET'] || die('ENV SECRET not found')
      @strength    = 'HS512'
    end

    def prepare
      if @common_file.exist?
        @tmp_file.write @common_file.read
      elsif @secret_file.exist?
        @tmp_file.write encoded_data
        Lux.info 'CREATED read file %s from secrets file' % @tmp_file
      elsif !@tmp_file.exist?
        Lux.info '@Secrets file "%s" created from template.' % @secret_file
        @tmp_file.write  <<~CFG
          default: &default

          production:
            <<: *default

          development:
            <<: *default
        CFG
      end

      @tmp_file.to_s
    end

    def finish
      write
      Cli.info 'Written secret file %s' % @secret_file
    end

    def write
      encoded = JWT.encode @tmp_file.read, @secret, @strength
      @secret_file.write %[# use "lux secrets" to edit this file\n\n#{encoded}]
    end

    def encoded_data
      if @secret_file.exist?
        data = @secret_file.read.split($/).last
        JWT.decode(data, @secret, true, { algorithm: @strength }).first
      else
        '{}'
      end
    end

    def to_h
      it =
      if @common_file.exist?
        @common_file.read
      else
        encoded_data
      end

      env  = Lux.env.to_s
      data = YAML.safe_load it, aliases: true

      data[env] || {}
    end

    def load
      to_h.to_hwia
    end
  end
end
