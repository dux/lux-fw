# Named relation cache groups - decouple a collection's cache from the
# master record's updated_at.
#
# `cache_key` embeds updated_at, so editing a master record busts every
# collection cached under it, even ones that did not change. Each named group
# instead keeps its own version stamp in cache, keyed off the stable `key`
# (no updated_at), and only the linked side bumps it.
#
# Declaration encodes intent by argument type:
#   named_caches :docs    # symbol -> model-backed; the Doc model is auto-wired
#                         #   to bump this group on create/update/destroy
#   named_caches 'feed'   # string -> free-form group, bumped manually
#
#   class Space < ApplicationModel
#     named_caches :boards, :docs   # Board/Doc invalidate automatically
#   end
#
#   space.cache_for(:docs, :home)   # -> versioned key for Lux.cache.fetch
#   space.cache_for_docs(:home)     # generated sugar, same key
#   space.cache_clear(:docs)        # bump version manually
#   space.clear_docs_cache          # generated sugar
#
# Auto-wiring (symbol groups): the child model is derived from the group name
# (:docs -> Doc) and linked back via the parent foreign key ("#{parent}_ref",
# e.g. space_ref). The hook is installed lazily on first cache access, which is
# boot-order safe: all models are loaded by the first request, and a group's
# cache does not exist until that first access anyway, so nothing is missed.

class Sequel::Model
  module ClassMethods
    def named_caches *names
      return (@named_caches ||= {}).keys if names.empty?

      @named_caches ||= {}
      names.flatten.each do |name|
        group = name.to_sym
        @named_caches[group] = name.is_a?(Symbol)   # symbol => model-backed

        define_method("cache_for_#{group}") { |*scope| cache_for(group, *scope) }
        define_method("clear_#{group}_cache") { cache_clear(group) }
      end
      @named_caches.keys
    end

    def named_cache? group
      (@named_caches || {}).key?(group.to_sym)
    end

    def named_cache_strict? group
      (@named_caches || {})[group.to_sym] == true
    end

    # lazily wire the child model to bump this group on write (once per group).
    # :boards -> Board, linked back via "#{self}_ref" (space_ref). Skips
    # silently when there is no such child/column - use cache_parent or a
    # manual clear for non-convention links.
    def bind_named_cache! group
      @bound_caches ||= {}
      return if @bound_caches[group]
      @bound_caches[group] = true

      child = group.to_s.singularize.classify.constantize?
      fk    = "#{to_s.underscore}_ref".to_sym
      return unless child && child.columns.include?(fk)

      pname = to_s
      child.after :cud do
        if pref = self[fk]
          Lux.cache.set "#{pname}/#{pref}/cv/#{group}", Time.now.to_f
        end
      end
    end

    # manual escape hatch for non-convention links (custom assoc / fk).
    # group defaults to this model's table name (Board -> :boards).
    #   cache_parent :space            # bump space :boards on write
    #   cache_parent :space, :archive
    def cache_parent assoc, group = to_s.tableize.to_sym
      after :cud do
        send(assoc)&.cache_clear(group)
      end
    end
  end

  module InstanceMethods
    # versioned cache key for a group; built from `key`, NOT `cache_key`,
    # so the master's updated_at never busts it.
    #   space.cache_for(:docs, :home) -> "Space/abc.../docs/1717761600.12/home"
    def cache_for group, *scope
      named_cache! group
      [key, group, cache_version(group), *scope].join('/')
    end

    # bump version(s) manually; child writes bump automatically (see bind)
    def cache_clear *groups
      groups = self.class.named_caches if groups.empty?
      groups.flatten.each do |g|
        named_cache! g
        Lux.cache.set cache_version_key(g), Time.now.to_f
      end
      true
    end

    private

    # guard the group, and for symbol groups validate the model + lazily wire
    # the child invalidation hook on first use.
    def named_cache! group
      group = group.to_sym

      unless self.class.named_cache?(group)
        raise ArgumentError, "#{self.class}: undeclared cache group #{group.inspect}, add `named_caches :#{group}`"
      end

      if self.class.named_cache_strict?(group)
        model = group.to_s.singularize.classify
        unless model.constantize?
          raise ArgumentError, "#{self.class}: cache group #{group.inspect} maps to no model #{model} (use string '#{group}' for a model-less group)"
        end
        self.class.bind_named_cache! group
      end
    end

    # read, lazily seeding the stamp on first use / after eviction
    def cache_version group
      vkey = cache_version_key group
      Lux.cache.get(vkey) || Time.now.to_f.tap { |t| Lux.cache.set vkey, t }
    end

    def cache_version_key group
      "#{key}/cv/#{group}"   # e.g. "Space/abc.../cv/docs"
    end
  end
end
