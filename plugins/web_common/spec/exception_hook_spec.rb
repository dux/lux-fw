require 'test_helper'
require 'fileutils'
require 'tmpdir'
require 'json'

require_relative '../load/lib/exception_writer'
require_relative '../loader'

# The plugin hook lives in loader.rb; loading just that file keeps this spec
# free of the model/db bootstrap the admin flow needs.
describe 'web_common exception hook' do
  before do
    @root = Pathname.new(Dir.mktmpdir('lux-hook-'))
    @prev_root = Lux.instance_variable_get(:@lux_app_root)
    Lux.instance_variable_set(:@lux_app_root, @root)
    Thread.current[:lux] = nil
  end

  after do
    Lux.instance_variable_set(:@lux_app_root, @prev_root)
    Thread.current[:lux] = nil
    FileUtils.remove_entry @root if @root.exist?
  end

  def rows
    path = @root.join('log/app.exceptions.log')
    path.read.lines.map { |line| JSON.parse(line) }
  end

  it 'writes the error through the hook' do
    err = RuntimeError.new('hooked')
    err.set_backtrace([@root.join('app/foo.rb:7:in `bar\'').to_s])

    Lux.error.log(err)

    _(rows.length).must_equal 1
    _(rows.first['message']).must_equal 'hooked'
  end

  it 'does not mask the original error when the writer fails' do
    prev = ExceptionWriter.instance_method(:write)
    ExceptionWriter.define_method(:write) { |**| raise 'writer down' }

    begin
      Lux.error.log(RuntimeError.new('original'))
    ensure
      ExceptionWriter.define_method(:write, prev)
    end

    _(true).must_equal true
  end
end
