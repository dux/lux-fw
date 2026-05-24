require 'test_helper'

describe Lux::Shell do
  describe '.exec' do
    it 'returns stripped stdout on success' do
      _(Lux.shell.exec('echo', 'hello')).must_equal 'hello'
    end

    it 'returns "" when the command emits nothing' do
      _(Lux.shell.exec('sh', '-c', 'true')).must_equal ''
    end

    it 'raises Lux::Shell::Error on non-zero exit with no block' do
      e = _{ Lux.shell.exec('sh', '-c', 'echo nope 1>&2; exit 2') }.must_raise Lux::Shell::Error
      _(e.err).must_include 'nope'
      _(e.command).must_equal ['sh', '-c', 'echo nope 1>&2; exit 2']
    end

    it 'raises when the binary is missing' do
      _{ Lux.shell.exec('this-binary-does-not-exist-xyz') }.must_raise Lux::Shell::Error
    end

    it 'calls block(err, out) on failure and returns nil' do
      seen_err = seen_out = nil
      result = Lux.shell.exec('sh', '-c', 'echo to-out; echo to-err 1>&2; exit 4') do |err, out|
          seen_err = err
          seen_out = out
        end
      _(result).must_be_nil
      _(seen_err).must_include 'to-err'
      _(seen_out).must_include 'to-out'
    end

    it 'empty block swallows failure silently and returns nil' do
      _(Lux.shell.exec('sh', '-c', 'exit 1') {}).must_be_nil
    end

    it 'block does not fire on success; return value is stdout' do
      called = false
      out = Lux.shell.exec('echo', 'ok') { called = true }
      _(called).must_equal false
      _(out).must_equal 'ok'
    end

    it 'passes env: through' do
      out = Lux.shell.exec('sh', '-c', 'echo $LUX_SHELL_TEST', env: { 'LUX_SHELL_TEST' => 'yes' })
      _(out).must_equal 'yes'
    end

    it 'passes chdir: through' do
      out = Lux.shell.exec('pwd', chdir: '/tmp')
      _(File.realpath(out)).must_equal File.realpath('/tmp')
    end

    it 'feeds stdin_data: into the child' do
      _(Lux.shell.exec('cat', stdin_data: 'piped-in')).must_equal 'piped-in'
    end

    it 'treats timeout as failure (raises by default)' do
      e = _{ Lux.shell.exec('sleep', '5', timeout: 0.1) }.must_raise Lux::Shell::Error
      _(e.message).must_match(/timed out/)
    end

    it 'timeout with block fires it with timeout message in err' do
      seen_err = nil
      Lux.shell.exec('sleep', '5', timeout: 0.1) { |err, _out| seen_err = err }
      _(seen_err).must_match(/timed out/)
    end

    it 'argv mode treats metachars as literal (no injection)' do
      _(Lux.shell.exec('echo', '; echo bad')).must_equal '; echo bad'
    end

    it 'shell:true requires a single string argv' do
      e = _{ Lux.shell.exec('echo', 'a', 'b', shell: true) }.must_raise ArgumentError
      _(e.message).must_match(/shell:true/)
    end

    it 'shell:true runs through /bin/sh' do
      _(Lux.shell.exec('echo a && echo b', shell: true)).must_equal "a\nb"
    end

    it 'rejects empty argv' do
      e = _{ Lux.shell.exec }.must_raise ArgumentError
      _(e.message).must_match(/no command given/)
    end
  end

  describe '.capture' do
    it 'returns merged stdout+stderr' do
      out = Lux.shell.capture('sh', '-c', 'echo to-out; echo to-err 1>&2')
      _(out).must_include 'to-out'
      _(out).must_include 'to-err'
    end

    it 'never raises on non-zero exit' do
      out = Lux.shell.capture('sh', '-c', 'echo bye 1>&2; exit 9')
      _(out).must_include 'bye'
    end

    it 'never raises when the binary is missing' do
      out = Lux.shell.capture('this-binary-does-not-exist-xyz')
      _(out).must_be_kind_of String
    end

    it 'is not stripped (full buffer including trailing newlines)' do
      _(Lux.shell.capture('printf', "a\nb\n")).must_equal "a\nb\n"
    end
  end

  describe '.stream' do
    it 'yields stdout lines as they arrive and returns merged output' do
      lines = []
      out = Lux.shell.stream('sh', '-c', 'echo a; echo b; echo c') { |l| lines << l }
      _(lines).must_equal %w[a b c]
      _(out).must_equal "a\nb\nc\n"
    end

    it 'requires a block' do
      e = _{ Lux.shell.stream('echo', 'hi') }.must_raise ArgumentError
      _(e.message).must_match(/block required/)
    end
  end

  describe 'Lux.shell shortcut' do
    it 'with no args returns the Lux::Shell module' do
      _(Lux.shell.equal?(Lux::Shell)).must_equal true
    end

    it 'with args delegates to .exec' do
      _(Lux.shell('echo', 'hi')).must_equal 'hi'
    end

    it 'with args raises on failure (like exec)' do
      _{ Lux.shell('sh', '-c', 'exit 1') }.must_raise Lux::Shell::Error
    end
  end

  describe '.which / .exists?' do
    it 'finds an executable on PATH' do
      _(Lux.shell.which('sh')).must_match(/\/sh\z/)
      _(Lux.shell.exists?('sh')).must_equal true
    end

    it 'returns nil for missing executables' do
      _(Lux.shell.which('definitely-not-a-binary-xyz')).must_be_nil
      _(Lux.shell.exists?('definitely-not-a-binary-xyz')).must_equal false
    end
  end

  describe 'output helpers' do
    it '.info writes to STDERR' do
      err = capture_stderr { Lux.shell.info 'hi' }
      _(err).must_match(/hi/)
    end

    it '.error writes to STDERR' do
      err = capture_stderr { Lux.shell.error 'oops' }
      _(err).must_match(/oops/)
    end

    it '.info accepts arrays' do
      err = capture_stderr { Lux.shell.info(['a', 'b']) }
      _(err).must_match(/a.*b/m)
    end
  end
end
