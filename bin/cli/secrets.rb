LuxCli.class_eval do
  desc :secrets, 'Show and compile secrets'
  def secrets
    require 'lux-fw'

    @secrets = Lux::Config::Secrets.new

    # create secret from template (config/secrets.enc)
    # or read file (tmp/secrets.yaml) if one exist
    unless @secrets.read_file.exist?
      if @secrets.secret_file.exist?
        @secrets.read_file.write @secrets.encoded_data
        Cli.info 'CREATED read file %s from secrets file' % @secrets.read_file
        # encoded = JWT.encode @secrets.read_file.read, @secrets.secret, @secrets.strength
        # @secrets.secret_file.write encoded
        # Cli.info 'Written secret file %s' % @secrets.secret_file
      else
        data  = "version: 1\n\n"
        data += %w[shared production development].map{ |it| "%s:\n  key: value" % it }.join("\n\n")
        @secrets.read_file.write data
        Cli.info '@Secrets file "%s" created from template.' % @secrets.read_file
      end
    end

    # edit ecrets file
    vim = `which vim`.chomp.or('vi')
    system '%s %s' % [vim, @secrets.read_file]

    # write secrets file if needed
    if !@secrets.secret_file.exist? || (@secrets.secret_file.ctime < @secrets.read_file.ctime)
      @secrets.write
      Cli.info 'Written secret file %s' % @secrets.secret_file
    end

    # show secret for easier debuging and dump secrets
    Cli.info 'secret: "%s"' % @secrets.secret
    Cli.info 'dump for ENV %s' % Lux.env
    puts @secrets.to_h.pretty_generate
  end
end
