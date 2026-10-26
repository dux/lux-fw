module Lux
  CACHE_SERVER ||= Lux::Cache.new
  VARS         ||= {}.to_lux_hash

  def var
    VARS
  end

  # Lux.cache.fetch ... -> pass to cache server
  # Lux.cache(:key) {}  -> in memory no clear cache
  def cache key=nil
    if block_given?
      raise ArgumentError.new('Cache key not given') unless key
      # presence check, not ||=, so a block returning nil/false is memoized once
      # read back after the write: Lux::Hash#[]= stores a converted copy of a ::Hash
      VARS[key] = yield unless VARS.key?(key)
      VARS[key]
    else
      CACHE_SERVER
    end
  end
end
