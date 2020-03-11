module Lux
  CACHE_SERVER ||= Lux::Cache.new
  CACHE        ||= {}.to_ch(:mutex)

  def var
    CACHE
  end

  # Lux.cache.fetch ... -> pass to cache server
  # Lux.cache(:key) {}  -> in memory no clear cache
  def cache key=nil
    if block_given?
      raise AargumentError.new('Cache key not given') unless key
      CACHE[key] ||= yield
    else
      CACHE_SERVER
    end
  end
end
