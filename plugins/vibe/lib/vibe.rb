# Vibe coding harness: a Sinatra page (chat + preview + diff + git) in front of a
# headless `opencode serve`, pinned to one git branch of the host app.
#
# Pure Ruby, no Lux boot: everything here runs from the `lux vibe:*` hammer tasks
# on the host and from the harness process inside the `vibe` container, and both
# configure themselves from ENV alone. See README.md in this plugin.

require 'fileutils'
require 'json'
require 'open3'
require 'timeout'

module Vibe
  class Error < StandardError; end

  DEFAULT_MODEL  ||= 'openrouter/anthropic/claude-sonnet-4.5'
  DEFAULT_BRANCH ||= 'vibe'

  module_function

  # checkout the harness works in (/app in the container)
  def root
    File.expand_path(ENV['VIBE_ROOT'] || Dir.pwd)
  end

  def plugin_root
    File.expand_path('..', __dir__)
  end

  # the only branch the harness writes to
  def branch
    ENV['VIBE_BRANCH'] || DEFAULT_BRANCH
  end

  # branch that gets merged into `branch` (never the other way round)
  def main
    ENV['VIBE_MAIN'] || 'main'
  end

  def port
    (ENV['VIBE_PORT'] || 4000).to_i
  end

  # what the browser iframes in the Preview tab
  def app_url
    ENV['VIBE_APP_URL'] || 'http://localhost:3000'
  end

  # what the harness process pings for the app status light (container-to-container)
  def app_health_url
    ENV['VIBE_APP_HEALTH_URL'] || app_url
  end

  def oc_url
    (ENV['VIBE_OC_URL'] || 'http://127.0.0.1:4096').sub(%r{/\z}, '')
  end

  # opencode model id: provider/model, e.g. openrouter/anthropic/claude-sonnet-4.5
  def model
    ENV['VIBE_MODEL'] || DEFAULT_MODEL
  end

  def openrouter_key
    ENV['OPENROUTER_API_KEY'].to_s.strip
  end

  # where the app keeps its compose files (config/docker by convention, root as fallback)
  def compose_file
    %w[config/docker/docker-compose.yml docker-compose.yml]
      .map { |f| File.join(root, f) }
      .find { |f| File.file?(f) }
  end

  # compose project the app container belongs to; docker-compose.yml `name:` wins
  # over the folder name, same as compose itself
  def compose_project
    return ENV['COMPOSE_PROJECT_NAME'] if ENV['COMPOSE_PROJECT_NAME']

    file = compose_file
    if file && (m = File.read(file).match(/^name:\s*['"]?([\w.-]+)/))
      m[1]
    else
      File.basename(root)
    end
  end

  def app_service
    ENV['VIBE_APP_SERVICE'] || 'app'
  end

  # Run a command, return [ok, output]. stdout and stderr are merged because the
  # interesting line of a failed git push/rebase lands on stderr. A timeout kills
  # the child instead of pinning a web thread on a hung network call.
  def run *argv, chdir: root, env: {}, timeout: 120, stdin: nil
    out = +''
    ok  = false

    Open3.popen2e(env, *argv, chdir: chdir) do |i, oe, thr|
      i.write(stdin) if stdin
      i.close
      begin
        Timeout.timeout(timeout) do
          out << oe.read.to_s
          ok = thr.value.success?
        end
      rescue Timeout::Error
        Process.kill('KILL', thr.pid) rescue nil
        out << "\n(timed out after #{timeout}s)"
        ok = false
      end
    end

    [ok, out]
  rescue Errno::ENOENT => e
    [false, e.message]
  end

  def run! *argv, **opts
    ok, out = run(*argv, **opts)
    raise Error, '%s failed: %s' % [argv.first(2).join(' '), first_line(out)] unless ok

    out
  end

  def first_line text
    text.to_s.strip.lines.map(&:strip).reject(&:empty?).first.to_s
  end
end

require_relative 'vibe/git'
require_relative 'vibe/restart'
require_relative 'vibe/opencode'
require_relative 'vibe/commit_message'
