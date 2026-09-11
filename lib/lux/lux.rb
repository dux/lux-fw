require_relative './root'

module ::Lux
  extend self

  # Sentinel for "no argument given". Use when nil/false are valid explicit values.
  # Compare with .equal?(Lux::UNSET), never ==.
  UNSET ||= Object.new.tap do |obj|
    def obj.inspect = 'Lux::UNSET'
    def obj.to_s    = inspect
  end.freeze

  def root
    @lux_app_root ||= Root.new(ENV.fetch('APP_ROOT') { Dir.pwd }).freeze
  end

  def fw_root
    @lux_fw_root ||= Pathname.new(__dir__).join('../..').expand_path.freeze
  end

  VERSION ||= fw_root.join('.version').read.chomp

  # Stable per-deploy identifier: same across restarts and across all app
  # servers of one deploy, changes when code/assets are redeployed. Used for
  # cache-busting (asset URLs, cache keys). Priority: explicit env (used as-is)
  # -> git sha -> newest ./app file mtime -> boot time. Mirrored into
  # ENV['DEPLOY_ID'] so child processes and tooling read the same value.
  # blank.rb (present?/presence) loads after this file, so stick to core checks.
  DEPLOY_ID ||=
    if (explicit = ENV['DEPLOY_ID']) && !explicit.empty?
      explicit
    else
      git = `git rev-parse --short=8 HEAD 2>/dev/null`.chomp
      raw =
        (git.empty? ? nil : git) ||
        root.files('app/**/*').map { |f| File.mtime(f).to_i rescue 0 }.max&.to_s ||
        Time.now.to_i.to_s
      ENV['DEPLOY_ID'] = raw.md5[0, 8]
    end

  # Cache-bust token for a cache keyed on source that can change.
  #
  # DEPLOY_ID is fixed for the life of a deploy, which is what you want in
  # production - one value per release, shared by every worker. In reload mode
  # it is the wrong answer: nothing about it moves when you edit a file, so a
  # cached view would sit there until its ttl ran out. There, stamp with the
  # mtime of the source that produced the entry instead.
  #
  #   Lux.deploy_stamp(__FILE__)
  def deploy_stamp source = nil
    return DEPLOY_ID unless source && Lux.reload?

    File.mtime(source).to_i.to_s rescue DEPLOY_ID
  end

  # simple block to calc block execution speed
  def speed
    render_start = Time.monotonic
    yield
    num = (Time.monotonic - render_start) * 1000
    if num > 1000
      '%s sec' % (num/1000).round(2)
    else
      '%s ms' % num.round(1)
    end
  end

  def app_caller
    app_line   = caller.find { |line| !line.include?('/lux-') && !line.include?('/.') && !line.include?('(eval)') }
    app_line ? Lux.root.pretty(app_line.split(':in ').first) : nil
  end
end
