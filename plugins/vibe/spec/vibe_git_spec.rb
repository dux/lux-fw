# Vibe::Git against throwaway repos: a bare "origin" with a main branch and a
# clone the harness works in. No Lux boot, no network.
#
#   cd ~/dev/gems/lux-fw && LUX_ENV=test bundle exec rspec plugins/vibe/spec

require 'tmpdir'
require 'fileutils'
require_relative '../loader'

RSpec.describe Vibe::Git do
  def sh(*argv, chdir:)
    ok, out = Vibe.run(*argv, chdir: chdir, timeout: 30)
    raise "#{argv.join(' ')} failed: #{out}" unless ok
    out
  end

  def git(*args, chdir: @work)
    sh('git', *args, chdir: chdir)
  end

  def write(name, content, chdir: @work)
    File.write File.join(chdir, name), content
  end

  def commit_all(msg, chdir: @work)
    git 'add', '-A', chdir: chdir
    git 'commit', '-q', '-m', msg, chdir: chdir
  end

  before do
    @tmp    = Dir.mktmpdir('vibe-git')
    @origin = File.join(@tmp, 'origin.git')
    @work   = File.join(@tmp, 'work')
    @other  = File.join(@tmp, 'other')

    sh 'git', 'init', '-q', '--bare', '-b', 'main', @origin, chdir: @tmp
    sh 'git', 'clone', '-q', @origin, @work, chdir: @tmp
    git 'config', 'user.name', 'spec'
    git 'config', 'user.email', 'spec@example.com'
    git 'checkout', '-q', '-b', 'main'
    write 'README.md', "hello\n"
    commit_all 'init'
    git 'push', '-q', '-u', 'origin', 'main'

    @env = ENV.to_h.slice('VIBE_ROOT', 'VIBE_BRANCH', 'VIBE_MAIN')
    ENV['VIBE_ROOT']   = @work
    ENV['VIBE_BRANCH'] = 'vibe'
    ENV['VIBE_MAIN']   = 'main'
  end

  after do
    %w[VIBE_ROOT VIBE_BRANCH VIBE_MAIN].each { |k| @env.key?(k) ? ENV[k] = @env[k] : ENV.delete(k) }
    FileUtils.rm_rf @tmp
  end

  describe '.ensure_branch!' do
    it 'creates vibe from main when missing and switches to it' do
      expect(described_class.current_branch).to eq 'main'
      expect(described_class.ensure_branch!).to eq 'vibe'
      expect(described_class.current_branch).to eq 'vibe'
      expect(git('rev-parse', 'vibe').strip).to eq git('rev-parse', 'main').strip
    end

    it 'refuses to switch with a dirty tree' do
      write 'README.md', "changed\n"
      expect { described_class.ensure_branch! }.to raise_error(Vibe::Error, /uncommitted/)
      expect(described_class.current_branch).to eq 'main'
    end

    it 'tracks origin/vibe when it exists but the local branch does not' do
      sh 'git', 'clone', '-q', @origin, @other, chdir: @tmp
      git 'config', 'user.name', 'o', chdir: @other
      git 'config', 'user.email', 'o@example.com', chdir: @other
      git 'checkout', '-q', '-b', 'vibe', chdir: @other
      write 'remote.txt', "x\n", chdir: @other
      commit_all 'remote vibe', chdir: @other
      git 'push', '-q', '-u', 'origin', 'vibe', chdir: @other

      described_class.ensure_branch!
      expect(described_class.current_branch).to eq 'vibe'
      expect(File).to exist(File.join(@work, 'remote.txt'))
      expect(described_class.upstream?).to be true
    end

    it 'is a no-op when already on vibe' do
      described_class.ensure_branch!
      write 'a.txt', "a\n"
      expect(described_class.ensure_branch!).to eq 'vibe' # dirty is fine here
    end
  end

  describe '.changes / .status / .diff' do
    before { described_class.ensure_branch! }

    it 'lists modified, added and deleted paths with counts' do
      write 'README.md', "hello\nworld\n"
      write 'new.txt', "one\ntwo\nthree\n"
      changes = described_class.changes
      by = changes.to_h { |c| [c[:path], c] }
      expect(by['README.md'][:status]).to eq 'modified'
      expect(by['README.md'][:add]).to eq 1
      expect(by['new.txt'][:status]).to eq 'added'
      expect(by['new.txt'][:add]).to eq 3

      s = described_class.status
      expect(s[:branch]).to eq 'vibe'
      expect(s[:on_vibe]).to be true
      expect(s[:dirty].length).to eq 2
      expect(s[:log].first[:subject]).to eq 'init'
    end

    it 'diffs tracked and untracked files' do
      write 'README.md', "hello\nworld\n"
      write 'new.txt', "fresh\n"
      expect(described_class.diff('README.md')).to include('+world')
      expect(described_class.diff('new.txt')).to include('+fresh')
      expect(described_class.diff).to include('+world').and include('+fresh')
    end
  end

  describe 'commit / push / pull' do
    before { described_class.ensure_branch! }

    it 'commits everything and pushes, setting the upstream' do
      write 'a.txt', "a\n"
      r = described_class.commit('add a')
      expect(r[:files]).to eq ['a.txt']
      expect(described_class.changes).to be_empty

      p = described_class.push
      expect(p[:pushed]).to be true
      expect(p[:incoming]).to eq []
      expect(git('ls-remote', '--heads', 'origin', 'vibe')).to include('refs/heads/vibe')
      expect(described_class.ahead_behind).to eq [0, 0]
    end

    it 'refuses an empty commit and an empty message' do
      expect { described_class.commit('x') }.to raise_error(Vibe::Error, /clean/)
      write 'a.txt', "a\n"
      expect { described_class.commit('  ') }.to raise_error(Vibe::Error, /empty/)
    end

    it 'rebases onto origin/vibe when the push is rejected' do
      write 'a.txt', "a\n"
      described_class.commit('add a')
      described_class.push

      # someone else pushes to vibe
      sh 'git', 'clone', '-q', '-b', 'vibe', @origin, @other, chdir: @tmp
      git 'config', 'user.name', 'o', chdir: @other
      git 'config', 'user.email', 'o@example.com', chdir: @other
      write 'b.txt', "b\n", chdir: @other
      commit_all 'remote b', chdir: @other
      git 'push', '-q', 'origin', 'vibe', chdir: @other

      write 'c.txt', "c\n"
      described_class.commit('add c')
      p = described_class.push
      expect(p[:pushed]).to be true
      expect(p[:incoming].length).to eq 1
      expect(File).to exist(File.join(@work, 'b.txt'))
      expect(git('log', '--format=%s', '-3').lines.map(&:strip)).to eq ['add c', 'remote b', 'add a']
    end

    it 'pulls with rebase and refuses a dirty tree' do
      described_class.push rescue nil
      write 'a.txt', "a\n"
      expect { described_class.pull }.to raise_error(Vibe::Error, /Commit or discard/)
    end
  end

  describe '.merge_main' do
    before { described_class.ensure_branch! }

    it 'merges new main commits into vibe' do
      # advance main on origin
      sh 'git', 'clone', '-q', '-b', 'main', @origin, @other, chdir: @tmp
      git 'config', 'user.name', 'o', chdir: @other
      git 'config', 'user.email', 'o@example.com', chdir: @other
      write 'main.txt', "m\n", chdir: @other
      commit_all 'main work', chdir: @other
      git 'push', '-q', 'origin', 'main', chdir: @other

      r = described_class.merge_main
      expect(r[:changed]).to be true
      expect(r[:source]).to eq 'origin/main'
      expect(File).to exist(File.join(@work, 'main.txt'))
      expect(described_class.current_branch).to eq 'vibe'
    end

    it 'aborts and reports conflicting files' do
      write 'README.md', "vibe version\n"
      described_class.commit('vibe readme')

      sh 'git', 'clone', '-q', '-b', 'main', @origin, @other, chdir: @tmp
      git 'config', 'user.name', 'o', chdir: @other
      git 'config', 'user.email', 'o@example.com', chdir: @other
      write 'README.md', "main version\n", chdir: @other
      commit_all 'main readme', chdir: @other
      git 'push', '-q', 'origin', 'main', chdir: @other

      expect { described_class.merge_main }.to raise_error(Vibe::Error, /conflicts in: README.md/)
      expect(git('status', '--porcelain').strip).to eq ''
      expect(File.read(File.join(@work, 'README.md'))).to eq "vibe version\n"
    end
  end

  describe '.reset! / .discard_file' do
    before { described_class.ensure_branch! }

    it 'throws away tracked changes and untracked files' do
      write 'README.md', "x\n"
      write 'junk.txt', "j\n"
      r = described_class.reset!
      expect(r[:discarded]).to contain_exactly('README.md', 'junk.txt')
      expect(described_class.changes).to be_empty
      expect(File).not_to exist(File.join(@work, 'junk.txt'))
    end

    it 'discards a single tracked or untracked file' do
      write 'README.md', "x\n"
      write 'junk.txt', "j\n"
      described_class.discard_file('junk.txt')
      expect(File).not_to exist(File.join(@work, 'junk.txt'))
      described_class.discard_file('README.md')
      expect(described_class.changes).to be_empty
    end

    it 'refuses when clean' do
      expect { described_class.reset! }.to raise_error(Vibe::Error, /clean/)
    end
  end
end
