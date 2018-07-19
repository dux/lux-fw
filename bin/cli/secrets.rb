LuxCli.class_eval do
  no_commands do
    def load_secret_file
      data = JWT.decode @secrets.secret_file.read, @secrets.secret, true, { algorithm: @secrets.strength }
      data.first
    end
  end

  desc :secrets, 'Show and compile secrets'
  def secrets
    require 'lux-fw'

    @secrets = Lux::Config::Secrets.new

    # create tempplate unless secret (config/secrets.enc) or read file (tmp/secrets.yaml) exist
    unless @secrets.read_file.exist? || @secrets.secret_file.exist?
      data  = "version: 1\n\n"
      data += %w[shared production development].map{ |it| "%s:\n  key: value" % it }.join("\n\n")
      @secrets.read_file.write data

      Cli.die '@Secrets file "%s" created from template.' % @secrets.read_file
    end

    # show secret for easier debuging
    Cli.info 'secret: "%s"' % @secrets.secret

    # version from secret is newer then local
    if @secrets.secret_file.exist? && @secrets.read_file.exist?
      local_version   = YAML.load(@secrets.read_file.read)['version'] || 0
      secrets_version = YAML.load(load_secret_file)['version'] || 0

      if secrets_version > local_version
        system "mv #{@secrets.read_file} #{@secrets.read_file}.backup"

        Cli.info "Secret file (v:#{secrets_version}) is newer then local file (v:#{local_version}), backuped local"
      end
    end

    # recreate read file from secret file if able
    if @secrets.secret_file.exist? && !@secrets.read_file.exist?
      begin
        @secrets.read_file.write load_secret_file
        Cli.info 'CREATED read file %s from secrets file' % @secrets.read_file
      rescue
        Cli.die 'Can not recreate tmp/secrets.yaml: %s' % $!.message
      end

    # write secrets file if needed
    elsif !@secrets.secret_file.exist? || (@secrets.secret_file.ctime < @secrets.read_file.ctime)
      begin
        encoded = JWT.encode @secrets.read_file.read, @secrets.secret, @secrets.strength
        @secrets.secret_file.write encoded
        Cli.info 'Written secret file %s' % @secrets.secret_file
      rescue
        Cli.die $!.message
      end
    end

    Cli.info 'dump for ENV %s' % Lux.env

    puts @secrets.to_h.pretty_generate
  end
end
