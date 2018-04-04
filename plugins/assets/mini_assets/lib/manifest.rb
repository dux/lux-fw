class MiniAssets::Manifest
  def initialize
    @manifest = MiniAssets::Opts.public_root.join('./manifest.json')
    @manifest.write '{"files":{}}' unless @manifest.exist?
    @json     = JSON.load @manifest.read
  end

  def add name, target
    return if @json['files'][name] == target

    @json['files'][name] = target
    @manifest.write JSON.pretty_generate(@json)
  end

  def get file
    @json['files'][file]
  end
end
