module MiniAssets::Opts
  extend self

  [:app, :tmp, :public].each do |folder|
    name  = '%s_root' % folder
    path  = Pathname.new './%s/assets' % folder

    Dir.mkdir(path) unless path.exist?

    define_method(name) { path }
  end

  def production?
    ENV['RACK_ENV'] == 'production'
  end
end
