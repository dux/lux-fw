# Adds `lux.header` accessor. Returns a per-request Lux::Header instance,
# memoized in current.var[:header_class]. First call instantiates it;
# subsequent calls return the same object for the request.
#
# Replaces the old `@header = PageMeta.new(...)` boilerplate in controllers.
class Lux::Current
  def header
    @var[:header_class] ||= Lux::Header.new
  end
end
