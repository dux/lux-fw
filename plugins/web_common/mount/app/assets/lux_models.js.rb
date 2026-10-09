# Model API index for app.m.<model>(ref) in dollar_api.js, one model per line
models = ModelApi.client_index.map { |key, opts| "  #{key.to_json}: #{opts.to_json}" }
"(window.Lux ||= {}).models = {\n#{models.join(",\n")}\n};"
