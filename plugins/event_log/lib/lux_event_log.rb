class LuxEventLog < ApplicationModel
  schema do
    tags Array[:text], index: true    # text[], GIN index; text so `tags @> ARRAY[..]` matches without casts
    data? String, max: 200
    json_data Hash             # jsonb
    created_at Time, index: true

    db :unlogged               # fast inserts, table truncated on PG crash
  end

  class << self
    def log tags, data = nil, json_data = {}
      create tags: Array(tags).map(&:to_s), data: data, json_data: json_data
    end

    # Fast path for hot code: single raw INSERT, no model instantiation,
    # validations or hooks. Truncates data to fit varchar(200) instead of
    # raising. Returns the generated ref.
    #   LuxEventLog.add tags: [:api, :v2], data: 'GET /users', json_data: { ms: 152 }
    def add tags: [], data: nil, json_data: {}
      ref = Lux::Utils::Ref.generate

      dataset.insert(
        ref:        ref,
        tags:       Sequel.pg_array(Array(tags).map(&:to_s), :text),
        data:       data&.to_s&.slice(0, 200),
        json_data:  Sequel.pg_jsonb(json_data),
        created_at: Sequel::CURRENT_TIMESTAMP
      )

      ref
    end
  end
end
