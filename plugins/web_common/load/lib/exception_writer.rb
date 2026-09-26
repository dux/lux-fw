require 'digest'
require 'json'
require 'pathname'
require 'time'
require 'fileutils'

# Append-only exception log. One occurrence becomes one compact JSON line in
# <Lux.root>/log/app.exceptions.log; dboss tails that file into its per-app
# exceptions tables. The file is flocked on append so concurrent processes
# never interleave a record.
class ExceptionWriter
  LOG_NAME ||= 'log/app.exceptions.log'

  def initialize error
    @error = error
  end

  # user: caller-supplied identity, no fallback. ip: falls back to the current
  # request when omitted. tags/description: caller-supplied, absent by default.
  def write user: nil, tags: nil, description: nil, ip: nil
    path = File.join(Lux.root.to_s, LOG_NAME)
    FileUtils.mkdir_p File.dirname(path)
    File.append path, JSON.generate(record(user, tags, description, ip || request_ip))
  end

  private

  def record user, tags, description, ip
    data = {}
    data['uid']         = uid
    data['dump']        = dump
    data['message']     = @error.message
    data['user']        = user if user.present?
    data['ip']          = ip if ip.present?
    data['tags']        = tags if tags.present?
    data['description'] = description if description.present?
    data['ts']          = Time.now.utc.iso8601(3)
    data
  end

  # Fingerprint of the first application frame: [file, line, class]. App paths
  # are relative to Lux.root; a fallback frame outside the app keeps its own
  # spelling. No backtrace means empty file and line 0.
  def uid
    line    = application_line
    file, n = line ? parse_location(line) : [nil, nil]
    file    = relativize(file) if file
    Digest::SHA256.hexdigest JSON.generate([file || '', n || 0, @error.class.name])
  end

  def dump
    @error.full_message highlight: false
  rescue StandardError
    (@error.backtrace || []).join($/)
  end

  def application_line
    locations = @error.backtrace
    return nil if locations.nil? || locations.empty?

    root = Lux.root.to_s
    locations.find { |line| under_root?(line, root) } || locations.first
  end

  def under_root? line, root
    file, = parse_location(line)
    return false unless file

    abs = File.expand_path(file)
    abs == root || abs.start_with?(root + '/')
  end

  def relativize file
    abs = File.expand_path(file)
    root = Lux.root.to_s
    return file unless abs == root || abs.start_with?(root + '/')

    Pathname.new(abs).relative_path_from(Pathname.new(root)).to_s
  end

  def parse_location line
    match = line.match(/\A(.+?):(\d+)/)
    match ? [match[1], match[2].to_i] : [nil, nil]
  end

  def request_ip
    return nil unless Thread.current[:lux]

    Lux.current.request.ip
  rescue StandardError
    nil
  end
end
