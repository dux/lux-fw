module LuxDeploy
  module Port
    module_function

    def resolve(ctx)
      return ctx.config[:port] if ctx.config[:port]

      used = used_ports(ctx)
      port = LuxDeploy.hash_port(ctx.app)
      1000.times do
        unless used.include?(port)
          ctx.config[:port] = port
          return port
        end
        port += 1
        port = 3000 if port > 3999
      end

      raise Error.new(
        'no free deploy port found',
        expected: 'a free port in 3000-3999',
        current: "used ports: #{used.sort.join(', ')}",
        need: 'free a port or pass --port',
        fix: 'lux deploy --port 3142',
        category: :preflight
      )
    end

    def used_ports(ctx)
      result = ctx.ssh.ssh("{ grep -Rho 'localhost:[0-9][0-9]*' /etc/caddy/sites 2>/dev/null || true; ss -ltn 2>/dev/null | awk 'NR>1 {print $4}'; }")
      result.stdout.scan(/:(\d{2,5})\b/).flatten.map(&:to_i).uniq
    end
  end
end
