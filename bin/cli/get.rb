LuxCli.class_eval do
  desc :get, 'Get single page by path "lux get /login"'
  method_option :body,   desc: 'Show body',    type: :boolean, aliases: "-b", default: false
  method_option :info,   desc: 'Show info',    type: :boolean, aliases: "-i", default: false
  method_option :type,   desc: 'Request type', type: :boolean, aliases: "-i", default: false
  def get path
    require './config/app'

    Cli.die "Use\n -b to show body\n -i to show info" unless options[:body] || options[:info]

    data = Lux.app.new(path).info

    if options[:body]
      puts data[:body]
    elsif options[:info]
      data[:body] = 'BODY lenght: %s kB' % (data[:body].length.to_f/1024).round(1)
      ap data.to_h
    end
  end
end
