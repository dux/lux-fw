module LuxAssets::Manifest
  MANIFEST = Lux.root.join('public/manifest.json')

  extend self

  def add name, path
    json = JSON.load MANIFEST.read

    return false if json['files'][name] == path

    json['files'][name] = path

    MANIFEST.write JSON.pretty_generate(json)

    true
  end

  def get name
    json = JSON.load MANIFEST.read
    json['files'][name]
  end

  ###

  MANIFEST.write '{"files":{}}' unless MANIFEST.exist?
end


