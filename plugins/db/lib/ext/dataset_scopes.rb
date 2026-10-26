# frozen_string_literal: true

# Convenience scopes layered on top of the query-builder primitives in
# `dataset_methods.rb`. Grouped by intent:
#
#   * ref-based scope        : for / where_ref
#   * ordering / extraction  : last_updated / desc / asc / latest / last / refs / pluck / ids
#   * array / tag search     : all_tags / where_any / where_all
#   * soft-delete / active   : not_deleted / deleted / activated / deactivated

Sequel::Model.dataset_module do
  # -- base default scope --------------------------------------------------

  # The unfiltered dataset. Reverse `link` (e.g. `link :comments`) resolves
  # through `RelatedModel.default`, so every model answers it out of the box.
  # Override per-model for custom default filtering/ordering:
  #   scope(:default) { not_deleted }
  def default
    self
  end

  # -- ref-based scope -----------------------------------------------------

  # Scope dataset to rows that point at obj through any recognised
  # *_ref / *_refs / parent_key / parent_type+parent_ref column.
  # See Sequel::Plugins::RefLinker.scope for the full shape table.
  #   Task.dataset.for(@user)        -> Task.where(user_ref: @user.ref)
  #   Note.dataset.where_ref(@user)  -> Note.where(parent_type:..., parent_ref:...)
  def for obj
    Sequel::Plugins::RefLinker.scope(self, obj)
  end
  alias :where_ref :for

  # -- ordering / extraction -----------------------------------------------

  # Card.last_updated
  # Card.last_updated epic_ref: @epic.ref
  def last_updated rules = nil
    field = model.db_schema[:updated_at] && :updated_at
    field ||= model.db_schema[:created_at] && :created_at
    field ||= :ref
    base = rules ? xwhere(rules) : self
    base.order(Sequel.desc(field)).first
  end

  def desc field = nil
    order(Sequel.desc(Sequel[model.table_name][(field || :created_at).to_sym]))
  end

  def asc
    order(Sequel.asc(Sequel[model.table_name][:created_at]))
  end

  def latest
    order(Sequel.desc(:updated_at))
  end

  # newest by created_at; an explicit order keeps Sequel's meaning instead
  # (`order(:imported_at).last` is the last by imported_at)
  def last num = nil
    return num ? super(num) : super() if opts[:order]

    base = xorder('%s desc' % :created_at)
    num ? base.limit(num).all : base.first
  end

  # Bare list of :ref values. Uses select_map (no model instantiation).
  #   Board.active.refs       -> ['abc...', 'def...', ...] (capped at 1000)
  #   Board.active.refs(50)   -> at most 50
  def refs cnt = nil
    limit(cnt || 1000).select_map(:ref)
  end

  def pluck field
    select_map field
  end

  # -- array / tag search --------------------------------------------------

  # Bucket.can.all_tags -> all_tags has to be last in the chain
  def all_tags opts = {}
    opts  = { tags: opts } if opts.is_a?(Symbol)
    limit = (opts[:limit] || 20).to_i
    field = Sequel.identifier(opts[:tags] || :tags)
    tags  = unordered.select(Sequel.function(:lower, Sequel.function(:unnest, field)).as(:tag))
    db.from(tags.as(:tags))
      .select(Sequel[:tag].as(:name), Sequel.function(:count, :tag).as(:cnt))
      .group(:tag).order(Sequel.desc(:cnt)).limit(limit)
      .map(&:to_lux_hash)
  end

  # Example: Job.where_any(@location.id, :location_ids).count
  def where_any data, field = :tags
    if data.present?
      data = [data] unless data.is_a?(Array)

      clauses = data.map { '?=any(%s)' % field }
      params  = data.map { |v| v.to_s }

      where(Sequel.lit(clauses.join(' or '), *params))
    else
      self
    end
  end

  # Filter records that have ALL specified tags (AND logic)
  # Example: Job.where_all(['ruby', 'remote'], :tags)
  def where_all data, field = :tags
    if data.present?
      data = [data] unless data.is_a?(Array)
      where(Sequel.lit("#{field}::text[] @> ?::text[]", Sequel.pg_array(data.map(&:to_s))))
    else
      self
    end
  end

  # -- soft-delete / active state -----------------------------------------

  def not_deleted
    model.db_schema[:is_deleted] ? where(Sequel[model.table_name][:is_deleted] => false) : self
  end

  def deleted
    model.db_schema[:is_deleted] ? where(Sequel[model.table_name][:is_deleted] => true) : self
  end

  def activated
    model.db_schema[:is_active] ? where(Sequel[model.table_name][:is_active] => true) : self
  end

  def deactivated
    model.db_schema[:is_active] ? where(Sequel[model.table_name][:is_active] => false) : self
  end
end
