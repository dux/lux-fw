class {{klass}}Exporter < Lux::JsonExporter
  define do
    json[:ref]  = model.ref
    json[:name] = model.name
  end
end
