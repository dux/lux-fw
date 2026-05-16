module LuxDeploy
  module Postgres
    module_function

    def ensure!(ctx)
      db = ctx.config[:db]
      user = db[:user]
      name = db[:name]
      ensure_role(ctx, user)
      ensure_database(ctx, name, user)
      Log.append(ctx, "db ensure ok name=#{name} user=#{user}")
    end

    def drop!(ctx)
      name = ctx.config.dig(:db, :name)
      cmd = "sudo -u postgres psql -v ON_ERROR_STOP=1 -d postgres -c #{LuxDeploy.sq("DROP DATABASE IF EXISTS #{name}")}"
      ctx.ssh.ssh!(cmd, category: :db, summary: 'database drop failed')
    end

    def ensure_role(ctx, user)
      result = psql(ctx, "SELECT 1 FROM pg_roles WHERE rolname='#{user}'")
      return if result.stdout.strip == '1'

      psql!(ctx, "CREATE ROLE #{user} LOGIN", summary: 'database role create failed')
    end

    def ensure_database(ctx, name, user)
      result = psql(ctx, "SELECT 1 FROM pg_database WHERE datname='#{name}'")
      return if result.stdout.strip == '1'

      psql!(ctx, "CREATE DATABASE #{name} OWNER #{user}", summary: 'database create failed')
    end

    def psql(ctx, sql)
      ctx.ssh.ssh("sudo -u postgres psql -v ON_ERROR_STOP=1 -d postgres -tAc #{LuxDeploy.sq(sql)}")
    end

    def psql!(ctx, sql, summary: 'postgres command failed')
      result = psql(ctx, sql)
      return result if result.success?

      raise CommandError.new(
        summary,
        result,
        expected: "sudo -u postgres psql executes #{sql.inspect}",
        need: 'local postgres is running and deploy user can sudo to postgres',
        fix: "ssh #{ctx.config[:host]} #{LuxDeploy.sq("sudo -u postgres psql -d postgres -c #{LuxDeploy.sq(sql)}")}",
        category: :db
      )
    end
  end
end
