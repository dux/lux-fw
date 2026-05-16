module LuxDeploy
  module Prepare
    module_function

    def run(ctx, with: [])
      validate_with!(with)
      user = ctx.ssh.ssh!('whoami', category: :preflight, summary: 'cannot resolve remote user').stdout.strip
      user = ctx.config[:user] if user.empty? && ctx.dry_run?
      ctx.remote_user = user
      script = remote_script(ctx, with)
      ctx.ssh.ssh!(script, category: :preflight, summary: 'server prepare failed')
      ctx.say "prepare ok host=#{ctx.config[:host]} ruby=#{ctx.ruby} with=#{with.join(',')}"
    end

    def validate_with!(items)
      caddy_items = items.select { |item| item == 'caddy' || item.start_with?('caddy-') }
      if caddy_items.size > 1
        raise Error.new(
          'conflicting caddy prepare options',
          expected: 'at most one of caddy or caddy-*',
          current: caddy_items.join(', '),
          need: 'choose one Caddy install variant',
          fix: 'lux deploy:prepare --with caddy-cloudflare',
          category: :preflight
        )
      end
    end

    def remote_script(ctx, with)
      ruby = ctx.ruby || '3.4.7'
      install_postgres = with.include?('postgres') ? '1' : '0'
      caddy_variant = with.find { |item| item == 'caddy' || item.start_with?('caddy-') }.to_s
      logrotate = LuxDeploy.render_template('logrotate.conf.erb', {})
      <<~SH
        set -e
        if command -v apt-get >/dev/null 2>&1; then
          sudo apt-get update
          sudo apt-get install -y build-essential libssl-dev libreadline-dev zlib1g-dev libyaml-dev libffi-dev git curl rsync
          [ #{install_postgres} = 1 ] && sudo apt-get install -y postgresql
          [ #{caddy_variant == 'caddy' ? '1' : '0'} = 1 ] && sudo apt-get install -y debian-keyring debian-archive-keyring apt-transport-https caddy
          [ #{caddy_variant.start_with?('caddy-') ? '1' : '0'} = 1 ] && sudo apt-get install -y golang
        elif command -v dnf >/dev/null 2>&1; then
          sudo dnf install -y gcc gcc-c++ make openssl-devel readline-devel zlib-devel libyaml-devel libffi-devel git curl rsync
          [ #{install_postgres} = 1 ] && sudo dnf install -y postgresql-server postgresql
          [ #{caddy_variant == 'caddy' ? '1' : '0'} = 1 ] && sudo dnf install -y caddy
          [ #{caddy_variant.start_with?('caddy-') ? '1' : '0'} = 1 ] && sudo dnf install -y golang
        elif command -v pacman >/dev/null 2>&1; then
          sudo pacman -Sy --noconfirm base-devel openssl readline zlib libyaml libffi git curl rsync
          [ #{install_postgres} = 1 ] && sudo pacman -S --noconfirm postgresql
          [ #{caddy_variant == 'caddy' ? '1' : '0'} = 1 ] && sudo pacman -S --noconfirm caddy
          [ #{caddy_variant.start_with?('caddy-') ? '1' : '0'} = 1 ] && sudo pacman -S --noconfirm go
        else
          echo unsupported distro >&2
          exit 1
        fi

        if [ ! -d "$HOME/.rbenv" ]; then
          git clone https://github.com/rbenv/rbenv.git "$HOME/.rbenv"
        fi
        mkdir -p "$HOME/.rbenv/plugins"
        if [ ! -d "$HOME/.rbenv/plugins/ruby-build" ]; then
          git clone https://github.com/rbenv/ruby-build.git "$HOME/.rbenv/plugins/ruby-build"
        else
          git -C "$HOME/.rbenv/plugins/ruby-build" pull --ff-only
        fi
        export PATH="$HOME/.rbenv/bin:$HOME/.rbenv/shims:$PATH"
        rbenv install -s #{ruby}
        rbenv global #{ruby}
        "$HOME/.rbenv/versions/#{ruby}/bin/gem" list -i bundler >/dev/null || "$HOME/.rbenv/versions/#{ruby}/bin/gem" install bundler --no-document

        #{caddy_plugin_install(caddy_variant)}

        [ #{install_postgres} = 1 ] && sudo systemctl enable --now postgresql
        if [ #{install_postgres} = 1 ]; then
          sudo -n true
          sudo -u postgres psql -c 'select 1' >/dev/null
        fi

        sudo mkdir -p /etc/caddy/sites
        sudo chown #{ctx.remote_user}:#{ctx.remote_user} /etc/caddy/sites
        sudo chmod 0755 /etc/caddy/sites
        sudo touch /etc/caddy/Caddyfile
        grep -qF 'import /etc/caddy/sites/*.caddy' /etc/caddy/Caddyfile || echo 'import /etc/caddy/sites/*.caddy' | sudo tee -a /etc/caddy/Caddyfile >/dev/null

        sudo mkdir -p /var/log/lux-deploy
        sudo chown #{ctx.remote_user}:#{ctx.remote_user} /var/log/lux-deploy
        sudo chmod 0755 /var/log/lux-deploy
        if ! sudo test -f /etc/logrotate.d/lux-deploy || ! printf %s #{LuxDeploy.sq(logrotate)} | sudo cmp -s - /etc/logrotate.d/lux-deploy; then
          printf %s #{LuxDeploy.sq(logrotate)} | sudo tee /etc/logrotate.d/lux-deploy >/dev/null
        fi

        ruby -v
        "$HOME/.rbenv/versions/#{ruby}/bin/bundle" -v
        command -v caddy >/dev/null 2>&1 && caddy version || true
        command -v psql >/dev/null 2>&1 && psql --version || true
      SH
    end

    def caddy_plugin_install(variant)
      return '' if variant.empty? || variant == 'caddy'

      provider = variant.sub('caddy-', '')
      module_name = "github.com/caddy-dns/#{provider}"
      <<~SH
        if ! command -v xcaddy >/dev/null 2>&1; then
          go install github.com/caddyserver/xcaddy/cmd/xcaddy@latest
        fi
        export PATH="$HOME/go/bin:$PATH"
        xcaddy build --with #{module_name}
        sudo install -m 0755 caddy /usr/local/bin/caddy
        sudo systemctl enable --now caddy
      SH
    end
  end
end
