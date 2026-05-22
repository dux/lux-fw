module ::Lux
  extend self

  # Sentinel for "no argument given". Use when nil/false are valid explicit values.
  # Compare with .equal?(Lux::UNSET), never ==.
  UNSET ||= Object.new.tap do |obj|
    def obj.inspect = 'Lux::UNSET'
    def obj.to_s    = inspect
  end.freeze

  def root
    @lux_app_root ||= Pathname.new(ENV.fetch('APP_ROOT') { Dir.pwd }).freeze
  end

  def fw_root
    @lux_fw_root ||= Pathname.new(__dir__).join('../..').expand_path.freeze
  end

  VERSION ||= fw_root.join('.version').read.chomp

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
    app_line ? app_line.split(':in ').first.sub(Lux.root.to_s, '.') : nil
  end
end

if $lux_start_time
  # for better start stats add $lux_start_time ||= Time.now to begginging of Gemfile
  $lux_start_time = [$lux_start_time, Time.now]
else
  $lux_start_time = Time.now
end
