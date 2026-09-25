# Vibe::Git against throwaway repos: a bare "origin" with a main branch and a
# clone the harness works in. No Lux boot, no network.
#
#   cd ~/dev/gems/lux-fw && bundle exec ruby -Ilib -Ispec plugins/vibe/spec/vibe_git_spec.rb

require 'test_helper'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/vibe'

describe Vibe::Git do
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

  # second clone standing in for another developer pushing to origin
  def other_clone(*args)
    sh 'git', 'clone', '-q', *args, @origin, @other, chdir: @tmp
    git 'config', 'user.name', 'o', chdir: @other
    git 'config', 'user.email', 'o@example.com', chdir: @other
  end

  def exist?(name)
    File.exist?(File.join(@work, name))
  end

  before do
    @tmp    = Dir.mktmpdir('vibe-git')
    @origin = File.join(@tmp, 'origin.git')
    @work   = File.join(@tmp, 'work')
    @other  = File.join(@tmp, 'other')

    # ensure_branch! writes safe.directory to the global config; keep that off ~/.gitconfig
    @env = ENV.to_h.slice('VIBE_ROOT', 'VIBE_BRANCH', 'VIBE_MAIN', 'GIT_CONFIG_GLOBAL')
    ENV['GIT_CONFIG_GLOBAL'] = File.join(@tmp, 'gitconfig')
    File.write ENV['GIT_CONFIG_GLOBAL'], ''

    sh 'git', 'init', '-q', '--bare', '-b', 'main', @origin, chdir: @tmp
    sh 'git', 'clone', '-q', @origin, @work, chdir: @tmp
    git 'config', 'user.name', 'spec'
    git 'config', 'user.email', 'spec@example.com'
    git 'checkout', '-q', '-b', 'main'
    write 'README.md', "hello\n"
    commit_all 'init'
    git 'push', '-q', '-u', 'origin', 'main'

    ENV['VIBE_ROOT']   = @work
    ENV['VIBE_BRANCH'] = 'vibe'
    ENV['VIBE_MAIN']   = 'main'
  end

  after do
    %w[VIBE_ROOT VIBE_BRANCH VIBE_MAIN GIT_CONFIG_GLOBAL].each { |k| @env.key?(k) ? ENV[k] = @env[k] : ENV.delete(k) }
    FileUtils.rm_rf @tmp
  end

  describe '.ensure_branch!' do
    it 'creates vibe from main when missing and switches to it' do
      assert_equal 'main', Vibe::Git.current_branch
      assert_equal 'vibe', Vibe::Git.ensure_branch!
      assert_equal 'vibe', Vibe::Git.current_branch
      assert_equal git('rev-parse', 'main').strip, git('rev-parse', 'vibe').strip
    end

    it 'branches from the local main even when it is ahead of origin' do
      write 'local.txt', "l\n"
      commit_all 'local only work'
      Vibe::Git.ensure_branch!
      assert_equal 'vibe', Vibe::Git.current_branch
      assert_equal git('rev-parse', 'main').strip, git('rev-parse', 'vibe').strip
      assert exist?('local.txt')
    end

    it 'refuses to switch with a dirty tree' do
      write 'README.md', "changed\n"
      err = assert_raises(Vibe::Error) { Vibe::Git.ensure_branch! }
      assert_match(/uncommitted/, err.message)
      assert_equal 'main', Vibe::Git.current_branch
    end

    it 'tracks origin/vibe when it exists but the local branch does not' do
      other_clone
      git 'checkout', '-q', '-b', 'vibe', chdir: @other
      write 'remote.txt', "x\n", chdir: @other
      commit_all 'remote vibe', chdir: @other
      git 'push', '-q', '-u', 'origin', 'vibe', chdir: @other

      Vibe::Git.ensure_branch!
      assert_equal 'vibe', Vibe::Git.current_branch
      assert exist?('remote.txt')
      assert_equal true, Vibe::Git.upstream?
    end

    it 'is a no-op when already on vibe' do
      Vibe::Git.ensure_branch!
      write 'a.txt', "a\n"
      assert_equal 'vibe', Vibe::Git.ensure_branch! # dirty is fine here
    end
  end

  describe '.repo_path!' do
    it 'returns a path inside the repo as given' do
      assert_equal 'README.md', Vibe::Git.repo_path!('README.md')
      assert_equal 'sub/../README.md', Vibe::Git.repo_path!('sub/../README.md')
    end

    it 'refuses an empty path' do
      err = assert_raises(Vibe::Error) { Vibe::Git.repo_path!('') }
      assert_match(/No path/, err.message)
      assert_raises(Vibe::Error) { Vibe::Git.repo_path!(nil) }
    end

    it 'refuses paths outside Vibe.root' do
      ['/etc/passwd', '../outside', 'sub/../../outside', '.', @work, "#{@work}-evil/x"].each do |path|
        err = assert_raises(Vibe::Error) { Vibe::Git.repo_path!(path) }
        assert_match(/outside the repo/, err.message)
      end
    end
  end

  describe '.changes / .status / .diff' do
    before { Vibe::Git.ensure_branch! }

    it 'lists modified, added and deleted paths with counts' do
      write 'README.md', "hello\nworld\n"
      write 'new.txt', "one\ntwo\nthree\n"
      changes = Vibe::Git.changes
      by = changes.to_h { |c| [c[:path], c] }
      assert_equal 'modified', by['README.md'][:status]
      assert_equal 1, by['README.md'][:add]
      assert_equal 'added', by['new.txt'][:status]
      assert_equal 3, by['new.txt'][:add]

      s = Vibe::Git.status
      assert_equal 'vibe', s[:branch]
      assert_equal true, s[:on_vibe]
      assert_equal 2, s[:dirty].length
      assert_equal 'init', s[:log].first[:subject]
    end

    it 'diffs tracked and untracked files' do
      write 'README.md', "hello\nworld\n"
      write 'new.txt', "fresh\n"
      assert_includes Vibe::Git.diff('README.md'), '+world'
      assert_includes Vibe::Git.diff('new.txt'), '+fresh'
      all = Vibe::Git.diff
      assert_includes all, '+world'
      assert_includes all, '+fresh'
    end

    it 'refuses to diff a path outside the repo' do
      File.write File.join(@tmp, 'outside'), "secret\n"
      ['/etc/passwd', '../outside'].each do |path|
        err = assert_raises(Vibe::Error) { Vibe::Git.diff(path) }
        assert_match(/outside the repo/, err.message)
      end
    end
  end

  describe 'commit / push / pull' do
    before { Vibe::Git.ensure_branch! }

    it 'commits everything and pushes, setting the upstream' do
      write 'a.txt', "a\n"
      r = Vibe::Git.commit('add a')
      assert_equal ['a.txt'], r[:files]
      assert_empty Vibe::Git.changes

      p = Vibe::Git.push
      assert_equal true, p[:pushed]
      assert_equal [], p[:incoming]
      assert_includes git('ls-remote', '--heads', 'origin', 'vibe'), 'refs/heads/vibe'
      assert_equal [0, 0], Vibe::Git.ahead_behind
    end

    it 'refuses an empty commit and an empty message' do
      err = assert_raises(Vibe::Error) { Vibe::Git.commit('x') }
      assert_match(/clean/, err.message)
      write 'a.txt', "a\n"
      err = assert_raises(Vibe::Error) { Vibe::Git.commit('  ') }
      assert_match(/empty/, err.message)
    end

    it 'rebases onto origin/vibe when the push is rejected' do
      write 'a.txt', "a\n"
      Vibe::Git.commit('add a')
      Vibe::Git.push

      # someone else pushes to vibe
      other_clone '-b', 'vibe'
      write 'b.txt', "b\n", chdir: @other
      commit_all 'remote b', chdir: @other
      git 'push', '-q', 'origin', 'vibe', chdir: @other

      write 'c.txt', "c\n"
      Vibe::Git.commit('add c')
      p = Vibe::Git.push
      assert_equal true, p[:pushed]
      assert_equal 1, p[:incoming].length
      assert exist?('b.txt')
      assert_equal ['add c', 'remote b', 'add a'], git('log', '--format=%s', '-3').lines.map(&:strip)
    end

    it 'pulls with rebase and refuses a dirty tree' do
      Vibe::Git.push rescue nil
      write 'a.txt', "a\n"
      err = assert_raises(Vibe::Error) { Vibe::Git.pull }
      assert_match(/Commit or discard/, err.message)
    end
  end

  describe '.merge_main' do
    before { Vibe::Git.ensure_branch! }

    it 'merges new main commits into vibe' do
      # advance main on origin
      other_clone '-b', 'main'
      write 'main.txt', "m\n", chdir: @other
      commit_all 'main work', chdir: @other
      git 'push', '-q', 'origin', 'main', chdir: @other

      r = Vibe::Git.merge_main
      assert_equal true, r[:changed]
      assert_equal 'origin/main', r[:source]
      assert exist?('main.txt')
      assert_equal 'vibe', Vibe::Git.current_branch
    end

    it 'aborts and reports conflicting files' do
      write 'README.md', "vibe version\n"
      Vibe::Git.commit('vibe readme')

      other_clone '-b', 'main'
      write 'README.md', "main version\n", chdir: @other
      commit_all 'main readme', chdir: @other
      git 'push', '-q', 'origin', 'main', chdir: @other

      err = assert_raises(Vibe::Error) { Vibe::Git.merge_main }
      assert_match(/conflicts in: README.md/, err.message)
      assert_equal '', git('status', '--porcelain').strip
      assert_equal "vibe version\n", File.read(File.join(@work, 'README.md'))
    end
  end

  describe '.reset! / .discard_file' do
    before { Vibe::Git.ensure_branch! }

    it 'throws away tracked changes and untracked files' do
      write 'README.md', "x\n"
      write 'junk.txt', "j\n"
      r = Vibe::Git.reset!
      assert_equal ['README.md', 'junk.txt'], r[:discarded].sort
      assert_empty Vibe::Git.changes
      refute exist?('junk.txt')
    end

    it 'discards a single tracked or untracked file' do
      write 'README.md', "x\n"
      write 'junk.txt', "j\n"
      Vibe::Git.discard_file('junk.txt')
      refute exist?('junk.txt')
      Vibe::Git.discard_file('README.md')
      assert_empty Vibe::Git.changes
    end

    it 'refuses to discard a path outside the repo' do
      File.write File.join(@tmp, 'outside'), "keep\n"
      err = assert_raises(Vibe::Error) { Vibe::Git.discard_file('../outside') }
      assert_match(/outside the repo/, err.message)
      assert_raises(Vibe::Error) { Vibe::Git.discard_file('/etc/passwd') }
      assert_equal "keep\n", File.read(File.join(@tmp, 'outside'))
    end

    it 'refuses when clean' do
      err = assert_raises(Vibe::Error) { Vibe::Git.reset! }
      assert_match(/clean/, err.message)
    end
  end
end
