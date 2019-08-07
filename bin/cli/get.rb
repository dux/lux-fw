LuxCli.class_eval do
  desc :get, 'Get single page by path "lux get /login"'
  method_option :hide, desc: 'Hide body', type: :boolean, aliases: "-h", default: false
  def get path
    require './config/application'

    data = Lux.app.render(path)
    data[:body] = 'BODY lenght: %s kB' % (data[:body].length.to_f/1024).round(1) if options[:hide]
    ap data
    puts '-h if you want to hide body' unless options[:hide]
  end
end
