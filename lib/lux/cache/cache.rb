# frozen_string_literal: true

module Lux
  class Cache
    def initialize
      @server = Lux::Cache::MemoryCache.new
    end

    # sert cache server
    # Lux.cache.server = :memory
    # Lux.cache.server = :memcached
    # Lux.cache.server = Dalli::Client.new('localhost:11211', { :namespace=>Digest::MD5.hexdigest(__FILE__)[0,4], :compress => true,  :expires_in => 1.hour })
    def server= name
      @server = if name.is_a?(Symbol)
        if name == :memcached
          require 'dalli'
          Dalli::Client.new('127.0.0.1:11211', { :namespace=>Digest::MD5.hexdigest(__FILE__)[0,4], :compress => true,  :expires_in => 1.hour })
        else
          "Lux::Cache::#{name.to_s.classify}Cache".constantize.new
        end
      else
        name
      end

      fetch('cache-test') { true }
    end

    def server
      @server
    end

    def read key
      return nil if (Lux.current.no_cache? rescue false)
      @server.get(key)
    end
    alias :get :read

    def read_multi *args
      @server.get_multi(*args)
    end
    alias :get_multi :read_multi

    def write key, data, ttl=nil
      ttl = ttl.to_i if ttl
      @server.set(key, data, ttl)
    end
    alias :set :write

    def delete key, data=nil
      @server.delete(key)
    end

    def fetch key, opts={}
      key = generate_key key

      opts = { ttl: opts } unless opts.is_a?(Hash)
      opts = opts.to_hwia :ttl, :force, :log, :if

      return yield if opts.if.is_a?(FalseClass)

      opts.ttl     = opts.ttl.to_i if opts.ttl
      opts.log   ||= Lux.config.log_to_stdout    unless opts.log.class   == FalseClass
      opts.force ||= Lux.current.try(:no_cache?) unless opts.force.class == FalseClass

      @server.delete key if opts.force

      Lux.log { " Cache.fetch.get ttl: #{opts.ttl.or(:nil)}, at: #{Lux.app_caller}".green }

      data = @server.fetch key, opts.ttl do
        speed = Lux.speed { data = yield }
        Lux.log " Cache.fetch.set speed: #{speed}, at: #{Lux.app_caller}".red if opts.log
        data
      end

      data
    end

    def is_available?
      set('lux-test', 9)
      get('lux-test') == 9
    end

    def generate_key *data
      keys = []

      for el in [data].flatten
        keys.push el.class.to_s
        keys.push el.id if el.respond_to?(:id)

        if el.respond_to?(:updated_at)
          keys.push el.updated_at
        elsif el.respond_to?(:created_at)
          keys.push el.created_at
        else
          keys.push el.to_s
        end
      end

      key = keys.join('-')

      Crypt.sha1(key)
    end

    def []= key, value
      @server.set key.to_s, value
      value
    end

    def [] key
      @server.get key.to_s
    end

  end
end

require_relative 'lib/memory'
