module Lux
  # shortcut for Lux::JsonExporter.define and .export
  #   Lux.json_exporter(Page) { prop :name }   - register exporter for Page
  #   Lux.json_exporter(Page.first)            - render Page.first
  def json_exporter name_or_object, opts = {}, &block
    if block
      Lux::JsonExporter.define name_or_object, &block
    else
      Lux::JsonExporter.new(name_or_object, opts).render
    end
  end
end
