require 'spec_helper'

describe Lux::Shell do
  describe '.exec' do
    it 'returns a Result with captured stdout' do
      r = Lux.shell.exec('echo', 'hello')
      expect(r).to be_a(Lux::Shell::Result)
      expect(r.out).to eq("hello\n")
      expect(r.err).to eq('')
      expect(r.success?).to be true
      expect(r.exitstatus).to eq(0)
      expect(r.duration).to be >= 0
      expect(r.command).to eq(['echo', 'hello'])
      expect(r.timed_out?).to be false
    end

    it 'captures stderr separately' do
      r = Lux.shell.exec('sh', '-c', 'echo to-err 1>&2')
      expect(r.out).to eq('')
      expect(r.err).to eq("to-err\n")
      expect(r.success?).to be true
    end

    it 'records a non-zero exit' do
      r = Lux.shell.exec('sh', '-c', 'exit 3')
      expect(r.success?).to be false
      expect(r.exitstatus).to eq(3)
    end

    it 'maps a missing command to exit 127' do
      r = Lux.shell.exec('this-binary-does-not-exist-xyz')
      expect(r.success?).to be false
      expect(r.exitstatus).to eq(127)
    end

    it 'raises Lux::Shell::Error when raise:true on failure' do
      expect {
        Lux.shell.exec('sh', '-c', 'echo nope 1>&2; exit 2', raise: true)
      }.to raise_error(Lux::Shell::Error) { |e|
        expect(e.result.exitstatus).to eq(2)
        expect(e.result.err).to include('nope')
      }
    end

    it 'does not raise when block is given on failure' do
      called = nil
      r = Lux.shell.exec('sh', '-c', 'exit 4') { |x| called = x }
      expect(called).to equal(r)
      expect(r.success?).to be false
    end

    it 'block on: :failure (default) skips on success' do
      called = false
      Lux.shell.exec('true') { called = true }
      expect(called).to be false
    end

    it 'block on: :success fires on success only' do
      hits = []
      Lux.shell.exec('true',  on: :success) { hits << :ok }
      Lux.shell.exec('false', on: :success) { hits << :ok }
      expect(hits).to eq([:ok])
    end

    it 'block on: :always fires either way' do
      hits = []
      Lux.shell.exec('true',  on: :always) { hits << :a }
      Lux.shell.exec('false', on: :always) { hits << :b }
      expect(hits).to eq([:a, :b])
    end

    it 'passes env: through' do
      r = Lux.shell.exec('sh', '-c', 'echo $LUX_SHELL_TEST', env: { 'LUX_SHELL_TEST' => 'yes' })
      expect(r.out.chomp).to eq('yes')
    end

    it 'passes chdir: through' do
      r = Lux.shell.exec('pwd', chdir: '/tmp')
      # /tmp resolves to /private/tmp on macOS; compare via realpath
      expect(File.realpath(r.out.chomp)).to eq(File.realpath('/tmp'))
    end

    it 'feeds stdin_data: into the child' do
      r = Lux.shell.exec('cat', stdin_data: 'piped-in')
      expect(r.out).to eq('piped-in')
    end

    it 'honours timeout: and marks the result timed_out?' do
      r = Lux.shell.exec('sleep', '5', timeout: 0.1)
      expect(r.timed_out?).to be true
      expect(r.success?).to be false
    end

    it 'argv mode treats metachars as literal (no injection)' do
      # if argv leaked into a shell, `; echo bad` would run; in argv it's just text
      r = Lux.shell.exec('echo', '; echo bad')
      expect(r.out).to eq("; echo bad\n")
    end

    it 'shell:true requires a single string argv' do
      expect { Lux.shell.exec('echo', 'a', 'b', shell: true) }.to raise_error(ArgumentError, /shell:true/)
    end

    it 'shell:true runs through /bin/sh' do
      r = Lux.shell.exec('echo a && echo b', shell: true)
      expect(r.out).to eq("a\nb\n")
    end

    it 'raises ArgumentError for an unknown on:' do
      expect { Lux.shell.exec('true', on: :weird) {} }.to raise_error(ArgumentError, /on:/)
    end

    it 'rejects empty argv' do
      expect { Lux.shell.exec }.to raise_error(ArgumentError, /no command given/)
    end
  end

  describe '.capture' do
    it 'returns stripped stdout' do
      expect(Lux.shell.capture('echo', 'value')).to eq('value')
    end

    it 'raises by default on failure' do
      expect { Lux.shell.capture('sh', '-c', 'exit 1') }.to raise_error(Lux::Shell::Error)
    end

    it 'block form suppresses the auto-raise' do
      seen = nil
      out = Lux.shell.capture('sh', '-c', 'exit 1') { |r| seen = r }
      expect(seen).to be_a(Lux::Shell::Result)
      expect(out).to eq('')
    end
  end

  describe '.run' do
    it 'returns true on success' do
      expect(Lux.shell.run('true')).to be true
    end

    it 'returns false on failure' do
      expect(Lux.shell.run('false')).to be false
    end
  end

  describe '.stream' do
    it 'yields stdout lines as they arrive and collects the full output' do
      lines = []
      r = Lux.shell.stream('sh', '-c', 'echo a; echo b; echo c') { |l| lines << l }
      expect(lines).to eq(%w[a b c])
      expect(r.out).to eq("a\nb\nc\n")
      expect(r.success?).to be true
    end

    it 'requires a block' do
      expect { Lux.shell.stream('echo', 'hi') }.to raise_error(ArgumentError, /block required/)
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

  describe 'Result helpers' do
    it 'lines / strip / err? / out!' do
      r = Lux.shell.exec('printf', "a\nb\nc\n")
      expect(r.lines).to eq(%w[a b c])
      expect(r.strip).to eq("a\nb\nc")
      expect(r.err?).to be false
      expect(r.out!).to eq("a\nb\nc")
    end

    it 'out! raises Lux::Shell::Error on failure' do
      r = Lux.shell.exec('sh', '-c', 'exit 9')
      expect { r.out! }.to raise_error(Lux::Shell::Error)
    end

    it 'to_h serialises the result' do
      h = Lux.shell.exec('echo', 'x').to_h
      expect(h[:exitstatus]).to eq(0)
      expect(h[:out]).to eq("x\n")
      expect(h[:success]).to be true
    end

    it 'json parses stdout' do
      r = Lux.shell.exec('echo', '{"a":1}')
      expect(r.json).to eq({ 'a' => 1 })
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
