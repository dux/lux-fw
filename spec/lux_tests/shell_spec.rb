require 'spec_helper'

describe Lux::Shell do
  describe '.exec' do
    it 'returns stripped stdout on success' do
      expect(Lux.shell.exec('echo', 'hello')).to eq('hello')
    end

    it 'returns "" when the command emits nothing' do
      expect(Lux.shell.exec('sh', '-c', 'true')).to eq('')
    end

    it 'raises Lux::Shell::Error on non-zero exit with no block' do
      expect { Lux.shell.exec('sh', '-c', 'echo nope 1>&2; exit 2') }
        .to raise_error(Lux::Shell::Error) { |e|
          expect(e.err).to include('nope')
          expect(e.command).to eq(['sh', '-c', 'echo nope 1>&2; exit 2'])
        }
    end

    it 'raises when the binary is missing' do
      expect { Lux.shell.exec('this-binary-does-not-exist-xyz') }
        .to raise_error(Lux::Shell::Error)
    end

    it 'calls block(err, out) on failure and returns nil' do
      seen_err = seen_out = nil
      result = Lux.shell.exec('sh', '-c', 'echo to-out; echo to-err 1>&2; exit 4') do |err, out|
          seen_err = err
          seen_out = out
        end
      expect(result).to be_nil
      expect(seen_err).to include('to-err')
      expect(seen_out).to include('to-out')
    end

    it 'empty block swallows failure silently and returns nil' do
      expect(Lux.shell.exec('sh', '-c', 'exit 1') {}).to be_nil
    end

    it 'block does not fire on success; return value is stdout' do
      called = false
      out = Lux.shell.exec('echo', 'ok') { called = true }
      expect(called).to be false
      expect(out).to eq('ok')
    end

    it 'passes env: through' do
      out = Lux.shell.exec('sh', '-c', 'echo $LUX_SHELL_TEST', env: { 'LUX_SHELL_TEST' => 'yes' })
      expect(out).to eq('yes')
    end

    it 'passes chdir: through' do
      out = Lux.shell.exec('pwd', chdir: '/tmp')
      expect(File.realpath(out)).to eq(File.realpath('/tmp'))
    end

    it 'feeds stdin_data: into the child' do
      expect(Lux.shell.exec('cat', stdin_data: 'piped-in')).to eq('piped-in')
    end

    it 'treats timeout as failure (raises by default)' do
      expect { Lux.shell.exec('sleep', '5', timeout: 0.1) }
        .to raise_error(Lux::Shell::Error, /timed out/)
    end

    it 'timeout with block fires it with timeout message in err' do
      seen_err = nil
      Lux.shell.exec('sleep', '5', timeout: 0.1) { |err, _out| seen_err = err }
      expect(seen_err).to match(/timed out/)
    end

    it 'argv mode treats metachars as literal (no injection)' do
      expect(Lux.shell.exec('echo', '; echo bad')).to eq('; echo bad')
    end

    it 'shell:true requires a single string argv' do
      expect { Lux.shell.exec('echo', 'a', 'b', shell: true) }
        .to raise_error(ArgumentError, /shell:true/)
    end

    it 'shell:true runs through /bin/sh' do
      expect(Lux.shell.exec('echo a && echo b', shell: true)).to eq("a\nb")
    end

    it 'rejects empty argv' do
      expect { Lux.shell.exec }.to raise_error(ArgumentError, /no command given/)
    end
  end

  describe '.capture' do
    it 'returns merged stdout+stderr' do
      out = Lux.shell.capture('sh', '-c', 'echo to-out; echo to-err 1>&2')
      expect(out).to include('to-out')
      expect(out).to include('to-err')
    end

    it 'never raises on non-zero exit' do
      out = Lux.shell.capture('sh', '-c', 'echo bye 1>&2; exit 9')
      expect(out).to include('bye')
    end

    it 'never raises when the binary is missing' do
      out = Lux.shell.capture('this-binary-does-not-exist-xyz')
      expect(out).to be_a(String)
    end

    it 'is not stripped (full buffer including trailing newlines)' do
      expect(Lux.shell.capture('printf', "a\nb\n")).to eq("a\nb\n")
    end
  end

  describe '.stream' do
    it 'yields stdout lines as they arrive and returns merged output' do
      lines = []
      out = Lux.shell.stream('sh', '-c', 'echo a; echo b; echo c') { |l| lines << l }
      expect(lines).to eq(%w[a b c])
      expect(out).to eq("a\nb\nc\n")
    end

    it 'requires a block' do
      expect { Lux.shell.stream('echo', 'hi') }.to raise_error(ArgumentError, /block required/)
    end
  end

  describe 'Lux.shell shortcut' do
    it 'with no args returns the Lux::Shell module' do
      expect(Lux.shell).to equal(Lux::Shell)
    end

    it 'with args delegates to .exec' do
      expect(Lux.shell('echo', 'hi')).to eq('hi')
    end

    it 'with args raises on failure (like exec)' do
      expect { Lux.shell('sh', '-c', 'exit 1') }.to raise_error(Lux::Shell::Error)
    end
  end

  describe '.which / .exists?' do
    it 'finds an executable on PATH' do
      expect(Lux.shell.which('sh')).to match(/\/sh\z/)
      expect(Lux.shell.exists?('sh')).to be true
    end

    it 'returns nil for missing executables' do
      expect(Lux.shell.which('definitely-not-a-binary-xyz')).to be_nil
      expect(Lux.shell.exists?('definitely-not-a-binary-xyz')).to be false
    end
  end

  describe 'output helpers' do
    it '.info writes to STDERR' do
      expect { Lux.shell.info 'hi' }.to output(/hi/).to_stderr
    end

    it '.error writes to STDERR' do
      expect { Lux.shell.error 'oops' }.to output(/oops/).to_stderr
    end

    it '.info accepts arrays' do
      expect { Lux.shell.info(['a', 'b']) }.to output(/a.*b/m).to_stderr
    end
  end
end
