# lux docker:vibe:* - the vibe coding harness from the host shell.
#
# init generates the docker/opencode files into the app (all under config/docker),
# run brings the compose stack up (app + db + vibe), the rest are the same
# git/restart actions the harness UI offers, for when a terminal is closer than a
# browser.
#
# Compose files live in config/docker and are run with --project-directory <root>,
# so every path inside them is relative to the app root - same convention as the
# app's own `lux docker:run`.

require 'erb'
require_relative '../loader'

module VibeHammer
  TEMPLATES ||= File.join(Vibe.plugin_root, 'templates')
  DOCKER    ||= 'config/docker'

  # generated file (relative to the app root) -> template
  FILES ||= {
    "#{DOCKER}/docker-compose.vibe.yml" => 'docker-compose.vibe.yml.erb',
    "#{DOCKER}/Dockerfile.vibe"         => 'Dockerfile.vibe.erb',
    "#{DOCKER}/entrypoint.vibe.sh"      => 'entrypoint.vibe.sh.erb',
    "#{DOCKER}/vibe/opencode.json"      => 'opencode.json.erb',
    "#{DOCKER}/vibe/instructions.md"    => 'instructions.md.erb',
  }

  module_function

  # .env lines the harness reads; git identity is copied from the host config so
  # commits made from inside the container carry the same author
  def env_defaults
    name  = Vibe.run('git', 'config', 'user.name',  timeout: 5).then { |ok, out| ok ? out.strip : '' }
    email = Vibe.run('git', 'config', 'user.email', timeout: 5).then { |ok, out| ok ? out.strip : '' }
    {
      'OPENROUTER_API_KEY' => '',
      'VIBE_MODEL'         => Vibe::DEFAULT_MODEL,
      'VIBE_GIT_NAME'      => name.empty?  ? 'vibe' : name,
      'VIBE_GIT_EMAIL'     => email.empty? ? 'vibe@localhost' : email,
    }
  end

  def template_vars
    lock    = File.join(Vibe.root, 'Gemfile.lock')
    bundler = File.file?(lock) && File.read(lock)[/BUNDLED WITH\n\s+([\d.]+)/, 1]
    rv_file = File.join(Vibe.root, '.ruby-version')
    ruby    = File.file?(rv_file) ? File.read(rv_file).strip.sub(/\Aruby-/, '') : RUBY_VERSION
    ok, out = Vibe.run('opencode', '--version', timeout: 5)

    {
      app_name:         Vibe.compose_project,
      ruby_version:     ruby,
      bundler_version:  bundler || '2.5.9',
      opencode_version: ok ? out.strip[/[\d.]+/] || 'latest' : 'latest',
      branch:           Vibe.branch,
      main:             Vibe.main,
      model:            Vibe.model,
      app_service:      Vibe.app_service,
      docker_dir:       DOCKER,
    }
  end

  def render name, vars
    src = File.read(File.join(TEMPLATES, name))
    ERB.new(src, trim_mode: '-').result_with_hash(vars)
  end

  # true when written, false when skipped
  def write_file rel, content, force:
    path = File.join(Vibe.root, rel)
    if File.exist?(path) && !force
      Hammer::Shell.say "  skip   #{rel} (exists, --force to overwrite)", :gray
      return false
    end
    FileUtils.mkdir_p File.dirname(path)
    File.write path, content
    File.chmod 0o755, path if rel.end_with?('.sh')
    Hammer::Shell.say "  write  #{rel}", :green
    true
  end

  def ensure_env_keys
    path  = File.join(Vibe.root, '.env')
    body  = File.file?(path) ? File.read(path) : ''
    added = []
    env_defaults.each do |key, default|
      next if body =~ /^#{key}=/
      body << "\n" unless body.empty? || body.end_with?("\n")
      body << "#{key}=#{default}\n"
      added << key
    end
    File.write path, body if added.any?
    added
  end

  def ensure_gitignore
    path = File.join(Vibe.root, '.gitignore')
    body = File.file?(path) ? File.read(path) : ''
    return false if body.lines.any? { |l| l.strip =~ %r{\A/?local/?\z|\A/?local/opencode/?\z} }

    body << "\n" unless body.empty? || body.end_with?("\n")
    body << "local/opencode\n"
    File.write path, body
    true
  end

  # base, then the vibe service, then the personal override last so its volume
  # mounts (live gem checkouts) win for both app and vibe
  def compose_cmd
    files = %w[docker-compose.yml docker-compose.vibe.yml docker-compose.override.yml]
      .map { |f| File.join(DOCKER, f) }
      .select { |f| File.file?(File.join(Vibe.root, f)) }
    unless files.include?(File.join(DOCKER, 'docker-compose.vibe.yml'))
      raise Vibe::Error, "no #{DOCKER}/docker-compose.vibe.yml here - run `lux docker:vibe:init` first"
    end

    "docker compose --project-directory #{Vibe.root} --profile vibe " + files.map { |f| "-f #{f}" }.join(' ')
  end

  # an override that remounts gems for `app` only leaves the vibe container with
  # the clone-mode mounts, which are empty on a live-mode machine
  def override_warning
    path = File.join(Vibe.root, DOCKER, 'docker-compose.override.yml')
    return nil unless File.file?(path)

    body = File.read(path)
    return nil unless body =~ /^\s{2}app:/ && body !~ /^\s{2}vibe:/

    "#{DOCKER}/docker-compose.override.yml overrides `app` but has no `vibe:` service - if it mounts live gem checkouts, mirror those volumes under `vibe:` too"
  end
end

namespace :docker do
  namespace :vibe do
    task :init do
      desc <<~TXT
        Generate the vibe harness files into this app, all under #{VibeHammer::DOCKER}/:
        docker-compose.vibe.yml, Dockerfile.vibe, entrypoint.vibe.sh, vibe/{opencode.json,instructions.md},
        plus OPENROUTER_API_KEY / VIBE_MODEL / VIBE_GIT_* lines in .env. Existing files are kept unless --force.
      TXT
      example 'docker:vibe:init'
      example 'docker:vibe:init --force'
      opt :force, type: :boolean, alias: :f, desc: 'overwrite generated files'
      proc do |opts|
        vars = VibeHammer.template_vars
        say.cyan "generating vibe files in #{Vibe.root}"
        VibeHammer::FILES.each do |rel, tpl|
          VibeHammer.write_file rel, VibeHammer.render(tpl, vars), force: opts[:force]
        end
        added = VibeHammer.ensure_env_keys
        say.green "  .env    added #{added.join(', ')}" if added.any?
        say.green '  .gitignore  added local/opencode' if VibeHammer.ensure_gitignore
        say ''
        say.yellow 'Set OPENROUTER_API_KEY in .env, then: lux docker:vibe:run' if Vibe.openrouter_key.empty?
        say.gray  "model: #{vars[:model]}  (VIBE_MODEL in .env, opencode id: provider/model)"
      end
    end

    task :run do
      desc <<~TXT
        Bring the stack up in vibe mode: app + db from #{VibeHammer::DOCKER}/docker-compose.yml plus the
        vibe harness (Sinatra on :4000 + opencode) from docker-compose.vibe.yml. Switches this
        checkout to the '#{Vibe.branch}' branch first (creates it from #{Vibe.main} when missing;
        refuses with a dirty tree). --stop tears it down.
      TXT
      example 'docker:vibe:run'
      example 'docker:vibe:run --build   # after Dockerfile.vibe changes'
      example 'docker:vibe:run --stop'
      opt :build,  type: :boolean, desc: 'rebuild images'
      opt :detach, type: :boolean, alias: :d, desc: 'run in the background'
      opt :stop,   type: :boolean, desc: 'docker compose down'
      proc do |opts|
        cmd = VibeHammer.compose_cmd
        exec "#{cmd} down" if opts[:stop]

        branch = Vibe::Git.ensure_branch!
        say.green "on branch #{branch}"
        say.yellow 'OPENROUTER_API_KEY is empty - the agent will not be able to call a model (set it in .env)' if Vibe.openrouter_key.empty?
        if (warning = VibeHammer.override_warning)
          say.yellow warning
        end
        say.gray  "harness  http://localhost:#{Vibe.port}"
        say.gray  "app      #{Vibe.app_url}"
        flags = [opts[:build] ? '--build' : nil, opts[:detach] ? '-d' : nil].compact.join(' ')
        exec "#{cmd} up #{flags}".strip
      end
    end

    task :server do
      desc 'Run the harness web app (Sinatra) in the foreground - the vibe container command. Configured from VIBE_* env.'
      example 'docker:vibe:server'
      example 'VIBE_OC_URL=http://127.0.0.1:4097 VIBE_PORT=4001 lux docker:vibe:server   # host debugging'
      proc do |_opts|
        require_relative '../lib/vibe/server'
        Vibe::Server.start!
      end
    end

    task :oc do
      desc "Run `opencode serve` for this checkout in the foreground, with #{VibeHammer::DOCKER}/vibe/opencode.json when present (host debugging helper)."
      example 'docker:vibe:oc'
      opt :port, type: :integer, default: 4096
      proc do |opts|
        cfg = File.join(Vibe.root, VibeHammer::DOCKER, 'vibe/opencode.json')
        ENV['OPENCODE_CONFIG'] ||= cfg if File.file?(cfg)
        say.gray "opencode serve on 127.0.0.1:#{opts[:port]} (config: #{ENV['OPENCODE_CONFIG'] || 'default'})"
        exec 'opencode', 'serve', '--hostname', '127.0.0.1', '--port', opts[:port].to_s, '--print-logs'
      end
    end

    task :status do
      desc 'Branch, dirty files, ahead/behind and recent commits of this checkout'
      proc do |_opts|
        s = Vibe::Git.status
        say.cyan "branch #{s[:branch]}#{s[:on_vibe] ? '' : "  (harness branch is #{s[:target]})"}  ahead #{s[:ahead]} behind #{s[:behind]}"
        if s[:dirty].any?
          say 'changes:'
          s[:dirty].each { |c| say "  #{c[:status][0].upcase}  #{c[:path]}  +#{c[:add]} -#{c[:del]}" }
        else
          say.gray 'working tree clean'
        end
        say 'log:'
        s[:log].first(8).each { |l| say.gray "  #{l[:sha]} #{l[:subject]} (#{l[:ago]})" }
      end
    end

    task :commit do
      desc 'Stage everything and commit on the vibe branch. Without -m the message is generated from the diff (OpenRouter).'
      example 'docker:vibe:commit -m "invoices: add due date column"'
      example 'docker:vibe:commit --push'
      opt :message, alias: :m, type: :string, desc: 'commit message (default: generated)'
      opt :push, type: :boolean, alias: :p, desc: 'push after committing'
      proc do |opts|
        msg = opts[:message].to_s.strip
        if msg.empty?
          say.gray 'generating commit message...'
          msg = Vibe::CommitMessage.generate
          say.cyan msg
        end
        r = Vibe::Git.commit(msg)
        say.green "committed #{r[:sha]} (#{r[:files].length} files)"
        if opts[:push]
          p = Vibe::Git.push
          say.green "pushed to origin/#{Vibe.branch}#{p[:incoming].any? ? " (rebased onto #{p[:incoming].length} incoming)" : ''}"
        end
      end
    end

    task :push do
      desc "Push the vibe branch to origin (rebases onto origin/#{Vibe.branch} if it moved)"
      proc do |_opts|
        r = Vibe::Git.push
        say.green "pushed #{r[:sha]} to origin/#{Vibe.branch}"
        say.gray "  rebased onto: #{r[:incoming].join(', ')}" if r[:incoming].any?
      end
    end

    task :pull do
      desc "Pull origin/#{Vibe.branch} (rebase); refuses with uncommitted changes"
      proc do |_opts|
        r = Vibe::Git.pull
        say.green(r[:changed] ? "pulled #{r[:incoming].length} commit(s), now at #{r[:sha]}" : 'already up to date')
      end
    end

    task :merge do
      desc "Merge #{Vibe.main} into #{Vibe.branch} (never the other way round - that is a review)"
      proc do |_opts|
        r = Vibe::Git.merge_main
        say.green(r[:changed] ? "merged #{r[:source]}: #{r[:incoming].length} commit(s), now at #{r[:sha]}" : "#{r[:source]} already merged")
      end
    end

    task :reset do
      desc 'Discard every uncommitted change (git reset --hard + clean -fd; ignored paths stay)'
      opt :yes, type: :boolean, alias: :y, desc: 'do not ask'
      proc do |opts|
        dirty = Vibe::Git.changes
        error 'working tree is clean' if dirty.empty?
        dirty.each { |c| say.gray "  #{c[:path]}" }
        next say.gray('cancelled') unless opts[:yes] || yes?("discard #{dirty.length} change(s)?")
        r = Vibe::Git.reset!
        say.green "discarded #{r[:discarded].length} change(s), at #{r[:sha]}"
      end
    end

    task :restart do
      desc 'Restart the app: soft = touch tmp/restart.txt (puma reload), --hard = restart the app container'
      opt :hard, type: :boolean, desc: 'docker restart of the app container'
      proc do |opts|
        r = opts[:hard] ? Vibe::Restart.hard : Vibe::Restart.soft
        say.green "restart #{r[:mode]} ok"
      end
    end

    task :logs do
      desc 'Follow the compose logs of the vibe and app services'
      proc do |_opts|
        exec "#{VibeHammer.compose_cmd} logs -f vibe #{Vibe.app_service}"
      end
    end
  end
end
