# Nav <-> model integration. Needs Sequel, so it stays in the db plugin; core
# Nav has no model knowledge.
#
# The ref *format* is core (named by Lux.config.ref_format, resolved through
# Lux::Application::Nav::Base). What lives here is the mapping from a ref in the
# URL to a record: the dispatch-key registry, and Nav#load_models.

module Lux
module Utils
module Ref
  extend self

  REGISTRY ||= {}

  # Ref.register(:ast, Asset)
  def register key, klass
    REGISTRY[key.to_sym] = klass
  end

  # every model that declares an abbr; memoized after first scan
  def models
    @models ||= Sequel::Model.descendants.select { |klass| (klass.abbr rescue nil).present? }
  end

  # resolve dispatch key (":ast") to model class
  def klass key
    REGISTRY[key.to_sym] || raise("Unsupported ref key #{key.inspect}")
  end

  # Ref.load("ast-abc123...")   -> Asset.find('abc123...')
  # Ref.load(:ast, "abc123...")
  def load key_ref, ref = nil
    if ref
      key = key_ref
    else
      key, ref = key_ref.to_s.split('-')
    end
    klass(key).find(ref)
  end

  def public_link key_link
    object = self.load key_link rescue nil
    if object
      %[<a href="#{object.path}">#{object.name || '-'} (#{key_link.split('-')[0]})</a>]
    else
      %[<span class="gray">#{key_link}</span>]
    end
  end
end
end
end

class Lux::Application::Nav
  # Resolve the URL's refs to records and export them as @object + @<model>
  # ivars on the running app.
  #
  # Driven by the path, not by a model list: every classified ref is named by
  # the segment in front of it (Nav::Base#path_before), which is matched against
  # each model's name, plural or abbr. A ref whose owner names no model, or
  # whose record does not exist, is skipped - the URL simply carries an id that
  # is not ours to load.
  #
  #   /boards/<ref>       or  /boa/<ref>   segment right before the ref
  #   /boa:<ref>                           abbr:ref path-qs (params[:boa])
  #
  # Every ref in the URL is resolved, in path order, so /orgs/<r1>/users/<r2>
  # exports both @org and @user. @object is the last one from the path - the
  # deepest, most specific resource.
  #
  # Only models that declare an `abbr` are reachable from a URL. Pass an
  # explicit list to narrow that further.
  #
  # Example - GET /boards/abc123, with Board.abbr == :boa:
  #   nav.load_models
  #   # => @object == @board == Board.find('abc123'); returns [board]
  #
  # ivars: false -> return the objects without setting ivars
  # pqs:   false -> ignore the abbr:ref form (API: a `doc[...]` POST must not reach find)
  def load_models models = nil, ivars: true, pqs: true
    # idempotent - a router that already declared the format keeps its result
    map_path

    app     = Lux.current.var[:lux_app] if ivars
    lookup  = load_models_index models
    found   = {}   # ivar name => record, in resolution order
    deepest = nil

    # the segment in front of a ref names its model
    path.grep(Lux::Application::Nav::Base).each do |segment|
      klass, name = lookup[load_models_key(segment.path_before)]
      next unless klass

      object = klass.find(segment.value) or next
      found[name] = object
      deepest     = object
    end

    if pqs
      # Nav#set_variables has already popped every trailing `abbr:ref` segment
      # into params, so /usr:<r1>/org:<r2> arrives as params[:usr] + params[:org].
      # Walk the params so all of them load, not just the first.
      # first entry wins, same precedence as the path index above
      by_abbr = lookup.values.uniq.each_with_object({}) do |(klass, name, abbr), out|
        out[abbr.to_sym] ||= [klass, name]
      end

      Lux.current.params.each do |key, value|
        klass, name = by_abbr[key.to_sym]
        next unless klass
        next if found.key?(name)

        # only the `abbr:ref` path-qs form yields a ref here; a nested form hash
        # (e.g. params[:doc] from a `doc[...]` POST when abbr == model name) is
        # not a ref and must not reach find()
        next unless value.is_a?(String) && value.present?

        object = klass.find(value) or next
        found[name] = object
      end
    end

    if app
      found.each { |name, object| app.instance_variable_set("@#{name}".to_sym, object) }
      app.instance_variable_set(:@object, deepest || found.values.last) unless found.empty?
    end

    found.values
  end

  private

  # Every URL spelling that names a model -> [klass, ivar_name, abbr].
  # Models without an abbr cannot be reached from a URL at all.
  #
  # Shallowest class first, so when two models claim the same key the base one
  # wins: an STI subclass inherits its parent's abbr (Pro < User both answer
  # :usr), and /usr:<ref> means the parent. The subclass keeps its own name, so
  # /pro/<ref> still reaches it.
  def load_models_index models
    models = Lux::Utils::Ref.models if models.nil?

    ordered = Array(models).sort_by { |klass| [klass.ancestors.length, klass.to_s] }

    ordered.each_with_object({}) do |klass, out|
      abbr = klass.abbr rescue nil
      next unless abbr.present?

      name  = klass.to_s.split('::').last.underscore
      entry = [klass, name, abbr]
      [name, name.pluralize, abbr].each { |key| out[load_models_key(key)] ||= entry }
    end
  end

  # `-` and `_` are the same character in a URL segment, as they are to the
  # router (Route#norm), so /business-premises and /business_premises both
  # resolve. A ref sitting directly behind another ref has no name and misses.
  def load_models_key segment
    segment.to_s.downcase.tr('-', '_')
  end
end
