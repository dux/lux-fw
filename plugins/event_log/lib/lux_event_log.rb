class LuxEventLog < ApplicationModel
  schema do
    tags Array[:text], index: true    # text[], GIN index; text so `tags @> ARRAY[..]` matches without casts
    data Hash                  # jsonb payload
    created_at Time, index: true

    db :unlogged               # fast inserts, table truncated on PG crash
  end

  class << self
    def log tags, data = {}
      create tags: Array(tags).map(&:to_s), data: data
    end

    # Fast path for hot code: single raw INSERT, no model instantiation,
    # validations or hooks. Returns the generated ref.
    #   LuxEventLog.add tags: [:api, :v2], data: { path: '/users', ms: 152 }
    def add tags: [], data: {}
      ref = Lux::Utils::Ref.generate

      dataset.insert(
        ref:        ref,
        tags:       Sequel.pg_array(Array(tags).map(&:to_s), :text),
        data:       Sequel.pg_jsonb(data || {}),
        created_at: Sequel::CURRENT_TIMESTAMP
      )

      ref
    end

    # Per-step counts for an ordered list of tags, oldest step first.
    #   LuxEventLog.funnel [:visit, :signup, :purchase], since: 7.days.ago
    # unique: 'user' counts distinct data->>'user' values (actor key inside
    # the data payload); unique: true counts distinct whole data values.
    # Returns [{ tag:, count:, pct:, step_pct: }, ...] - pct is vs the
    # first step, step_pct vs the previous one (nil for the first).
    def funnel tags, since: nil, till: nil, unique: nil
      scope = dataset
      scope = scope.xwhere('created_at >= ?', since) if since
      scope = scope.xwhere('created_at < ?',  till)  if till

      counts = Array(tags).map(&:to_s).map do |tag|
        step = scope.where_all(tag, :tags)

        cnt = if unique == true
          step.distinct.select(:data).count
        elsif unique
          step
            .xwhere('data->>? is not null', unique.to_s)
            .distinct.select(Sequel.lit('data->>?', unique.to_s))
            .count
        else
          step.count
        end

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
  end
end
