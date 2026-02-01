# http://lvh.me:3000/css/admin
# CssCompile.route_map('css', './app/assets/auto/%s/css')

# require 'sass-embedded'
# require 'base64'

# class CssCompile
#   class << self
#     def files dir
#       Dir.glob(File.join(dir, '**/*.{css,scss}')).sort
#     end

#     def route_map root, mask
#       if root == lux.nav.root
#         non_compressed = Lux.env.dev? && lux.nav.format != :c
#         dir = mask % [lux.nav.path[1]]

#         key = "css:#{dir}:#{non_compressed}"
#         if Lux.env.dev?
#           last_modified = CssCompile.files(dir).map { |f| File.mtime(f) }.max
#           key += ":#{last_modified.to_f}"
#         end

#         css_data = Lux.cache.fetch key do
#           data = CssCompile.new(dir: dir)
#           data = data.send(non_compressed ? :css_with_embedded_source_map : :css_compressed)
#           data
#         end

#         lux.response.body css_data, content_type: 'text/css'
#       end
#     end
#   end

#   ###

#   def initialize(file: nil, dir: nil)
#     case
#     when file
#       @filename = Pathname.new(file)
#     when dir
#       @dir = dir
#       build_temp_file_from_dir
#     else
#       raise ArgumentError, "Either file or dir parameter is required"
#     end
#   end

#   def css_expanded
#     compile(style: :expanded, source_map: false).css
#   end

#   def css_with_embedded_source_map
#     result = compile(style: :expanded, source_map: true, source_map_include_sources: true)
#     embed_source_map(result.css, result.source_map)
#   end

#   def css_compressed
#     compile(style: :compressed, source_map: false).css
#   end

#   def css
#     if self.class.non_compressed
#       css_with_embedded_source_map
#     else
#       css_compressed
#     end
#   end

#   private

#   def build_temp_file_from_dir
#     @filename = Tempfile.new

#     files = self.class.files(@dir)
#     files.each do |file|
#       # Use @import with absolute path for proper source tracking
#       name = file.split('/assets/', 2)[1]
#       @filename.puts "\n/* #{name} */"
#       @filename.puts "@import '#{File.absolute_path(file)}';"
#     end

#     @filename.flush
#     @filename.rewind
#   end

#   def compile(**options)
#     # Silence common deprecation warnings
#     options[:silence_deprecations] ||= ['color-functions', 'global-builtin', 'import']
#     Sass.compile(@filename.path, **options)
#   rescue Sass::CompileError => e
#     raise "Sass compilation error: #{e.message}"
#   end

#   def embed_source_map(css, source_map)
#     base64_map = Base64.strict_encode64(source_map)
#     "#{css}\n/*# sourceMappingURL=data:application/json;base64,#{base64_map}*/"
#   end
# end
