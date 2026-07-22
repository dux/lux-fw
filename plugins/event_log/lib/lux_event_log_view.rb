# Saved admin views. Every event_log admin page keeps its full state in the
# URL, so a saved view is just a name -> path (with query string) record.
class LuxEventLogView < ApplicationModel
  schema do
    name String, max: 100, index: true
    path :text
    created_at Time
    updated_at Time
  end

  class << self
    # upsert by name - re-saving under the same name replaces the path
    def store name, path
      row = first(name: name.to_s)
      row ? row.update(path: path.to_s) : create(name: name.to_s, path: path.to_s)
    end

    # GET-side save/forget for the admin views (same pattern as the
    # exception_logger resolve toggle): ?save_as=<name> stores the current
    # URL, ?forget=<name> deletes, both redirect back to the clean URL so a
    # refresh / back-button does not repeat the mutation. Returns the clean
    # path, used by the views to highlight the active saved view.
    def apply lux
      # _r is the framework redirect-loop tracker - transient, keep it out
      # of the canonical path
      qs = lux.params.reject { |k, _| %w(save_as forget _r).include?(k.to_s) }

      clean = lux.request.path.dup
      clean += '?' + URI.encode_www_form(qs) if qs.length > 0

      if name = lux.params[:save_as]
        store name, clean
        lux.response.redirect_to clean, silent: true
      elsif name = lux.params[:forget]
        where(name: name.to_s).delete
        lux.response.redirect_to clean, silent: true
      end

      clean
    end
  end
end
