class LuxEventLog < ApplicationModel
  schema do
    tags Array[:text], index: true    # text[], GIN index; text so `tags @> ARRAY[..]` matches without casts
    user_ref? :ref, index: true
    parent_key? String
    info? String, max: 200
    data Hash                  # jsonb payload
    created_at Time, index: true

    db :unlogged               # fast inserts, table truncated on PG crash
  end

  class << self
    def log tags, payload = nil, user_ref: nil, parent_key: nil, info: nil, data: nil, **details
      data = (payload || {}).merge(data || {}).merge(details)
      create tags: Array(tags).map(&:to_s), user_ref: user_ref, parent_key: parent_key, info: info, data: data
    end

    # Fast path for hot code: single raw INSERT, no model instantiation,
    # validations or hooks. Returns the generated ref.
    #   LuxEventLog.add tags: [:api], user_ref: user.ref, data: { path: '/users' }
    def add tags: [], user_ref: nil, parent_key: nil, info: nil, data: {}
      ref = Lux::Utils::Ref.generate

      dataset.insert(
        ref:        ref,
        tags:       Sequel.pg_array(Array(tags).map(&:to_s), :text),
        user_ref:   user_ref,
        parent_key: parent_key,
        info:       info&.to_s&.slice(0, 200),
        data:       Sequel.pg_jsonb(data || {}),
        created_at: Sequel::CURRENT_TIMESTAMP
      )

      ref
    end

    # Per-step counts for an ordered list of tags, oldest step first.
    #   LuxEventLog.funnel [:visit, :signup, :purchase], since: 7.days.ago
    # unique: :user_ref uses the indexed column; any other name counts
    # distinct data->>name values; unique: true counts whole data values.
    # Returns [{ tag:, count:, pct:, step_pct: }, ...] - pct is vs the
    # first step, step_pct vs the previous one (nil for the first).
    def funnel tags, since: nil, till: nil, unique: nil
      scope = dataset
      scope = scope.xwhere('created_at >= ?', since) if since
      scope = scope.xwhere('created_at < ?',  till)  if till

      counts = Array(tags).map(&:to_s).map do |tag|
        step = scope.where_all(tag, :tags)

        cnt = funnel_count step, unique

        [tag, cnt]
      end

      first = counts.first&.last.to_i
      prev  = nil

      counts.map do |tag, cnt|
        row = {
          tag:      tag,
          count:    cnt,
          pct:      first > 0 ? (100.0 * cnt / first).round(1) : 0.0,
          step_pct: prev && prev > 0 ? (100.0 * cnt / prev).round(1) : nil,
        }
        prev = cnt
        row
      end
    end

    private

    def funnel_count step, unique
      if unique == true
        step.distinct.select(:data).count
      elsif unique.to_s == 'user_ref'
        step.exclude(user_ref: nil).distinct.select(:user_ref).count
      elsif unique
        step
          .xwhere('data->>? is not null', unique.to_s)
          .distinct.select(Sequel.lit('data->>?', unique.to_s))
          .count
      else
        step.count
      end
    end
  end
end
