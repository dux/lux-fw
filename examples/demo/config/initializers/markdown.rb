# Enable Markdown (.md) views. Tilt knows the md/markdown/mkd extensions
# but keeps them in its lazy map; lux resolves view extensions by scanning
# Tilt's eager template_map only (Lux::Template / Controller#template_file_exists?),
# so register the adapter eagerly here to make .md files resolve.
require 'tilt/commonmarker'

Tilt.register Tilt::CommonMarkerTemplate, 'md', 'markdown', 'mkd'
