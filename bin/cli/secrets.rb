LuxCli.class_eval do
  desc :secrets, 'Show and compile secrets'
  def secrets
    require 'lux-fw'

    @secrets = Lux::Config::Secrets.new

    unless @secrets.read_file.exist? || @secrets.secret_file.exist?
      data = %w[shared production development].map{ |it| "%s:\n  key: value" % it }.join("\n\n")
      @secrets.read_file.write data

      Cli.die '@Secrets file "%s" created from template.' % @secrets.read_file
    end

    if !@secrets.read_file.exist?
      begin
        decoded = JWT.decode @secrets.secret_file.read, @secrets.secret, true, { algorithm: @secrets.strength }
        @secrets.read_file.write decoded.first
        Cli.info 'created %s' % @secrets.read_file
      rescue; end
    elsif !@secrets.secret_file.exist? || @secrets.secret_file.ctime < @secrets.read_file.ctime
      begin
        encoded = JWT.encode @secrets.read_file.read, @secrets.secret, @secrets.strength
        @secrets.secret_file.write encoded
        Cli.info 'written %s' % @secrets.secret_file
      rescue; end
    else
      Cli.info 'all good, no need to compile secrets'
    end

    Cli.info 'secret: "%s"' % @secrets.secret
    Cli.info 'dump for ENV %s' % Lux.env

    puts @secrets.to_h.pretty_generate
  end
end
