LuxCli.class_eval do
  desc :secrets, 'Edit, show and compile secrets'
  def secrets
    require 'lux-fw'

    @secrets = Lux::Secrets.new

    # edit ecrets file
    vim = `which vim`.chomp.or('vi')
    system '%s %s' % [vim, @secrets.prepare]

    @secrets.finish

    # show secret for easier debuging and dump secrets
    Cli.info 'secret: "%s"' % @secrets.secret
    Cli.info 'dump for ENV %s' % Lux.env

    puts @secrets.to_h.pretty_generate
  end
end
