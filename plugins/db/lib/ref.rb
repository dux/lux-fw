# Ref - opaque short ID generator + resolver used for primary keys / references.
#
# Apps register dispatch keys via `Ref.register(:ast, Asset)` and resolve with
# `Ref.load("ast-abc...")`. Apps may also reopen Ref to override `klass` or
# `public_link` if they need richer behaviour.

module Lux
module Utils
module Ref
  extend self

  LOWERCASE_KEYS ||= 'abcdefghijklmnopqrstuvwxyz0123456789'
  MIXEDCASE_KEYS ||= 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'

  REGISTRY ||= {}

  # validates the canonical 16-char form. accepts "key-ref" composite by
  # stripping the prefix before splitting on ':'.
  def is? text
    text.length == 16 && text =~ /^[a-z0-9]+$/
  end

  # Ref.generate                  -> 16-char lowercase+digits
  # Ref.generate(8)               -> 8-char lowercase+digits
  # Ref.generate(16, uppercase: true) -> 16-char mixed-case+digits
  def generate length = 16, uppercase: false
    keys = uppercase ? MIXEDCASE_KEYS : LOWERCASE_KEYS
    Array.new(length) { keys[rand(keys.length)] }.join
  end

  # Ref.register(:ast, Asset)
  def register key, klass
    REGISTRY[key.to_sym] = klass
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

# Nav integration kept here so core Nav stays free of Ref/plugin knowledge.
class Lux::Application::Nav
  # Classify 16-char Ref segments to :ref markers; returns the last extracted ref.
  # /orgs/cw7r.../edit -> ['orgs', :ref, 'edit'], nav.ref == 'cw7r...'
  def extract_ref!
    path :ref do |el|
      Lux::Utils::Ref.is?(el) ? el : nil
    end
  end

  # Load one model per captured ref, mapping each class to the ref at the same
  # position in nav.refs (so call right after extract_ref!). Loads only what it
  # can - a class with no matching ref (or no record) yields nil in that slot;
  # never raises. The block runs for every loaded object, typically a policy
  # check. Returns the loaded objects.
  #
  # A trailing options Hash is supported; ivars: true exports each object as an
  # instance variable on the running Application instance (@org, @user, ...),
  # which the router then copies into the controller.
  #
  #   # /orgs/<ref>/users/<ref>
  #   nav.ref_load_objects Org, User, ivars: true do |object|
  #     object.can.read!
  #   end
  #   # -> @org, @user available in the controller and templates
  def ref_load_objects *classes, &block
    opts    = classes.last.is_hash? ? classes.pop : {}

    objects = classes.each_with_index.map do |klass, i|
      next unless (ref = @refs[i])
      object = klass.find(ref)
      block.call(object) if block && object
      object
    end

    if opts[:ivars] && (app = Lux.current.var[:lux_app])
      classes.each_with_index do |klass, i|
        name = klass.to_s.split('::').last.underscore
        app.instance_variable_set("@#{name}".to_sym, objects[i])
      end
    end

    objects
  end

  # Resolve the model named by the path segment right before the first ref, load
  # it by nav.ref, and export @object + @<model> on the running Application
  # instance (the router copies them into the controller and views). Returns the
  # object, or nil when the URL carries no ref or the segment isn't a known
  # model. Reads from the path, not from :key path-qs params.
  #   /foo/bar/org/<ref>/baz  ->  @object = @org = Org.find('<ref>')   (org, not foo)
  def ref_object
    return unless ref

    i = path.index(:ref)
    return unless i && i > 0

    model = path[i - 1].to_s.classify
    return unless Object.const_defined?(model)

    app    = Lux.current.var[:lux_app] or return
    object = model.constantize.find(ref)

    app.instance_variable_set(:@object, object)
    app.instance_variable_set("@#{object.class.to_s.underscore}".to_sym, object)
    object
  end

  # Load the URL-referenced models from the given candidates, exporting @object +
  # @<model> on the running Application instance. Each candidate is matched by
  # class name or its 3-letter abbr, in two URL forms:
  #   /foo/bar/projects/<ref>  or  /foo/bar/pro/<ref>   (segment right before the ref)
  #   /foo/bar/pro:REF                                   (abbr:ref path-qs -> params[:pro])
  # Candidates that don't define an abbr are matched by name only (skipped for
  # abbr matching). Returns the loaded objects. Pass ivars: false to skip the
  # @object/@<model> export and only get the objects back.
  #   nav.load_models [Project, User]
  def load_models models, opts = {}
    i   = path.index(:ref)
    seg = (i && i > 0) ? path[i - 1].to_s : nil
    app = Lux.current.var[:lux_app] unless opts[:ivars] == false

    models.filter_map do |klass|
      name = klass.to_s.split('::').last.underscore
      abbr = klass.abbr rescue nil   # nil when the model defines no abbr -> name match only

      value =
        if ref && seg && [name, name.pluralize, abbr&.to_s].include?(seg)
          ref
        elsif abbr && (v = Lux.current.params[abbr]).present?
          v
        end

      next unless value
      object = klass.find(value) or next

      if app
        app.instance_variable_set(:@object, object)
        app.instance_variable_set("@#{name}".to_sym, object)
      end
      object
    end
  end
end
