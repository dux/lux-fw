# uset to run task in remote servers

# Duxstrano.add :app, 'user@1.2.3.4:/home/deployer/app', log: 'log/production.log'
# Duxstrano.add :db, 'root@2.3.4.5', config: '/etc/postgresql/12/main/pg_hba.conf', log: '/var/log/postgresql/postgresql-12-main.log.1'

# create remote tasks, pass server argument if you want to toogle server
# def rtask *args, &block
#   name = args.shift
#   desc args.shift if args.first.is_a?(String)
#   task name, args do |_, argumnets|
#     Duxstrano.new argumnets, &block
#     puts ''
#   end
# end

# rake remote:bash
# rake remote:bash[db]
# namespace :remote do
#   rtask :bash, 'bash shell in app root', :server do
#     run 'bash -i'
#   end
# end

###

if $0.ends_with?('/rake') || ENV['DUXSTRANO'] == 'true'
  class Duxstrano
    HOSTS ||= {}

    class << self
      def add name, server, opts={}
        opts = opts.to_hwia
        opts[:user], opts[:ip], opts[:path] = server.split(/[\@:]/)
        opts[:path] ||= '~'
        opts[:name] = name
        HOSTS[name] = opts
      end
    end

    ###

    def initialize opts, &block
      server = opts[:server].to_s == '' ? HOSTS.keys.first : opts[:server].to_sym
      set_host server
      @args = opts
      instance_exec opts, &block
    end

    def set_host name
      @host = HOSTS[name] || die("Server [%s] not defined" % name)
    end

    # host :db -> set host to :db
    # host(:db) { ... } -> execute in context
    # host -> @host
    def host name = nil
      if name
        old_host = @host
        set_host name

        if block_given?
          yield
          @host = old_host
        end
      else
        @host
      end
    end

    # return true or execute block if we are on a right host
    def host? name
      return false unless host.name == name
      yield if block_given?
      true
    end

    def die text
      puts text.red
      exit
    end

    def local command
      puts command.yellow
      system command
      puts '-'
    end

    # invoke local rake command
    def invoke name
      local 'rake %s' % name
    end

    # run on remote server
    def run command, opts={}
      command = command.join('; ') if command.is_a?(Array)
      command = command.sub(/^bundle\s/, '/home/deployer/.rbenv/shims/bundle ')
      command = command.gsub(/'/, %{\\\\'})
      full    =  "ssh -t #{@host.user}@#{@host.ip} $'cd #{@host.path}; #{command}';"
      puts full.magenta
      system full
      die 'Error in last command, exiting' unless $?.success?
    end

    # sync '/foo/bar'
    # sync '/foo/bar', '/other_root_and_not_foo'
    def sync source, destination=nil, opts={}
      destination ||= source.sub(/\/\w+$/, '')

      die 'sync source cant end with "/" - %s' % source if source.end_with?('/')
      die 'sync destination cant end with "/" - %s' % destination if destination.end_with?('/')

      folder = source.split('/').last

      # hack for root folder
      if source == '.'
        destination = ''
        folder = ''
      else
        folder = '/%s/' % folder
      end

      sync = ['rsync -rph --executability --delete']
      sync.push %w{/.env /.git /.gems /log tmp/* node_modules/* /cache *.sqlite}
        .map { |it| "--exclude '%s'" % it }
        .join(' ')
      sync.push "#{source} #{@host.user}@#{@host.ip}:#{@host.path}/#{destination}/"
      sync = sync.join(' ').gsub('//', '/')

      local sync
    end

    # upload a file
    def upload source, destination=nil
      destination ||= source
      destination   = destination.sub(/^\.\//, '%s/' % @host.path)

      local "scp #{source} #{@host.user}@#{@host.ip}:#{destination}"
    end

    # download a file
    def download source, destination=nil
      destination ||= source
      source        = source.sub(/^\.\//, '%s/' % @host.path)

      local "scp #{@host.user}@#{@host.ip}:#{source} #{destination}"
    end
  end

  # create remote tasks, pass server argument if you want to toogle server
  def rtask *args, &block
    name = args.shift
    desc args.shift if args.first.is_a?(String)
    task name, args do |_, argumnets|
      Duxstrano.new argumnets, &block
      puts ''
    end
  end
end
