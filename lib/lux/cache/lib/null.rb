class Lux::Cache::NullCache
  def set key, data, ttl=nil
    data
  end

  def get key
    nil
  end

  def fetch key, ttl=nil
    yield
  end

  def delete key
    nil
  end

  def get_multi *args
    {}
  end
end