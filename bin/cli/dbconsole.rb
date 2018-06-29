LuxCli.class_eval do
  desc :dbconsole, 'Get PSQL console for current database'
  def dbconsole
    require './config/environment'

    system "psql '%s'" % ENV.fetch('DB_URL') { Lux.secrets.db_url }
  end
end