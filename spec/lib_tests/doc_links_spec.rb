require 'test_helper'

# Relative links in the framework docs are how agents navigate the repo, so a
# link to a moved or deleted file fails here instead of misleading a reader.
describe 'documentation links' do
  it 'resolves every relative link in README / AGENTS markdown' do
    root  = Lux.fw_root.to_s
    files = Dir.glob('{README.md,AGENTS.md,lib/**/*.md,plugins/**/*.md,bin/**/*.md}', base: root)
    broken = []

    files.each do |file|
      File.read(File.join(root, file)).scan(/\]\(([^)\s]+)\)/).flatten.each do |link|
        next if link.start_with?('http', '#', 'mailto:')

        path = link.split('#').first
        full = File.expand_path(path, File.join(root, File.dirname(file)))
        broken.push "#{file}: #{link}" unless File.exist?(full)
      end
    end

    assert_empty broken
  end
end
