# Dev-only schema map. Introspects every registered model schema into a flat
# structure the /dev/schema visualiser renders as cards + relation arrows.
#
# Source of truth is Lux::Schema's SCHEMA_STORE (Lux.schema type: :model) plus
# the *_ref / *_refs column conventions (same shapes RefLinker.detect uses):
#   <name>_ref   -> belongs_to <Name>
#   <name>_refs  -> has_many   <Name>
# The timestamps audit quartet is split out so the card can collapse it.

class SchemaMap
  AUDIT ||= %i[created_at updated_at creator_ref updater_ref].freeze

  # short labels for the field type column
  TYPES ||= {
    string: 'str',  integer: 'int',  boolean: 'bool', datetime: 'datetime',
    text:   'text', ref:     'ref',  email:   'email', url:      'url',
    domain: 'domain', decimal: 'dec', model:  'model', time:     'time',
    date:   'date'
  }.freeze

  class << self
    # [{ model:, table:, abbr:, fields:[...], audit:[...], relations:[...] }]
    def export
      Lux.schema(type: :model).filter_map { |name| describe(name) }.sort_by { |m| m[:model] }
    rescue
      []
    end

    private

    def describe name
      schema = Lux.schema?(name) or return
      klass  = name.to_s.constantize
      return unless klass < Sequel::Model

      main, audit = schema.rules.partition { |field, _| !AUDIT.include?(field) }

      {
        model:     klass.to_s,
        table:     klass.table_name.to_s,
        abbr:      klass.respond_to?(:abbr) ? klass.abbr : nil,
        fields:    main.map  { |f, o| field(f, o) },
        audit:     audit.map { |f, o| field(f, o) },
        relations: relations(main)
      }
    rescue NameError
      nil
    end

    def field name, opts
      {
        name:     name,
        type:     type_label(opts),
        required: !!opts[:required],
        unique:   !!opts.dig(:meta, :unique),
        fk:       opts[:type] == :ref
      }
    end

    def type_label opts
      base = TYPES[opts[:type]] || opts[:type].to_s
      opts[:array] ? "#{base}[]" : base
    end

    # outgoing edges from *_ref / *_refs columns (audit fields already removed)
    def relations fields
      fields.filter_map do |name, opts|
        next unless opts[:type] == :ref
        col = name.to_s
        if opts[:array] || col.end_with?('_refs')
          { field: name, to: col.sub(/_refs?$/, '').singularize.classify, kind: :has_many }
        elsif col.end_with?('_ref')
          { field: name, to: col.sub(/_ref$/, '').classify, kind: :belongs_to }
        end
      end
    end
  end
end
