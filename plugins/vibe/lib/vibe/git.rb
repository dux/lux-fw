# Git operations for the harness. Every write goes through ensure_branch!, so the
# working copy can only ever be on Vibe.branch when something is committed,
# pushed, merged or discarded. Ported from the app-side AiControlApi (commit with
# push-rebase-retry, discard) and extended with pull, merge main, per-file discard
# and the branch guard.

module Vibe
  module Git
    GIT_TIMEOUT ||= 120

    # a push that cannot authenticate has to fail in a second, not block on a
    # credential prompt nobody is there to answer
    GIT_ENV ||= {
      'GIT_TERMINAL_PROMPT' => '0',
      'GIT_SSH_COMMAND'     => 'ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new',
    }

    module_function

    # --- low level ---------------------------------------------------------

    # [ok, output] - a non-zero exit is an outcome, not an error
    def git? *args, timeout: GIT_TIMEOUT
      Vibe.run('git', *args, env: GIT_ENV, timeout: timeout)
    end

    # output, or raise Vibe::Error with the first useful line
    def git *args, timeout: GIT_TIMEOUT
      ok, out = git?(*args, timeout: timeout)
      raise Error, 'git %s failed: %s' % [args.first, Vibe.first_line(out)] unless ok

      out.strip
    end

    def lines text
      text.to_s.lines.map(&:strip).reject(&:empty?)
    end

    # --- branch guard ------------------------------------------------------

    def current_branch
      git 'rev-parse', '--abbrev-ref', 'HEAD'
    end

    def on_branch?
      current_branch == Vibe.branch
    end

    def branch_exists? name
      git?('rev-parse', '--verify', '--quiet', "refs/heads/#{name}").first
    end

    def remote_branch_exists? name
      git?('rev-parse', '--verify', '--quiet', "refs/remotes/origin/#{name}").first
    end

    # The working copy lands on Vibe.branch or the call raises. Switching with a
    # dirty tree is refused rather than stashed on the caller's behalf - the
    # harness must never lose uncommitted work silently.
    def ensure_branch!
      # inside the container the checkout is owned by the host uid; without this
      # every git call is refused as "dubious ownership"
      git? 'config', '--global', '--add', 'safe.directory', Vibe.root

      current = current_branch
      return current if current == Vibe.branch

      dirty = changes
      if dirty.any?
        raise Error, 'On %s with %d uncommitted change(s) - commit or stash them before the harness can switch to %s' % [current, dirty.length, Vibe.branch]
      end

      if branch_exists?(Vibe.branch)
        git 'checkout', Vibe.branch
      else
        # a quick fetch so a branch that already lives on origin is tracked, not
        # forked; offline is fine, the local refs are used as they are
        git? 'fetch', '--quiet', 'origin', timeout: 20

        if remote_branch_exists?(Vibe.branch)
          git 'checkout', '--track', "origin/#{Vibe.branch}"
        else
          # the local main is what the developer is looking at (it may be ahead of
          # origin with unpushed work); origin/main only when there is no local one
          base = if branch_exists?(Vibe.main) then Vibe.main
                 elsif remote_branch_exists?(Vibe.main) then "origin/#{Vibe.main}"
                 else raise Error, 'No %s branch to create %s from' % [Vibe.main, Vibe.branch]
                 end
          # --no-track: the upstream of vibe is origin/vibe (set by the first push),
          # never main - otherwise ahead/behind would be measured against main
          git 'checkout', '--no-track', '-b', Vibe.branch, base
        end
      end

      Vibe.branch
    end

    # --- status ------------------------------------------------------------

    # [{path, status, add, del}] for every changed path (tracked + untracked)
    def changes
      stats = {}
      lines(git('diff', '--numstat', 'HEAD')).each do |l|
        add, del, path = l.split("\t", 3)
        next unless path
        stats[path] = [add.to_i, del.to_i] # "-" for binary -> 0
      end

      # raw output: the first column of a porcelain line is significant whitespace
      ok, raw = git?('status', '--porcelain=v1', '--untracked-files=all')
      raise Error, 'git status failed: %s' % Vibe.first_line(raw) unless ok

      raw.lines.map(&:chomp).reject { |l| l.strip.empty? }.map do |l|
        code = l[0, 2]
        path = l[3..].to_s
        path = path.split(' -> ').last if code.include?('R')
        path = path.gsub(/\A"|"\z/, '')

        status = case
                 when code.include?('?') then 'added'
                 when code.include?('A') then 'added'
                 when code.include?('D') then 'deleted'
                 when code.include?('R') then 'renamed'
                 else 'modified'
                 end

        add, del = stats[path]
        if add.nil? && status == 'added'
          full = File.join(Vibe.root, path)
          add  = File.file?(full) ? File.foreach(full).count : 0 rescue 0
          del  = 0
        end

        { path: path, status: status, add: add.to_i, del: del.to_i }
      end
    end

    def upstream?
      git?('rev-parse', '--abbrev-ref', '--symbolic-full-name', '@{u}').first
    end

    def ahead_behind
      return [0, 0] unless upstream?

      a, b = git('rev-list', '--left-right', '--count', 'HEAD...@{u}').split
      [a.to_i, b.to_i]
    end

    def log n = 20
      lines(git('log', "-#{n}", '--format=%h%x09%s%x09%ar%x09%an')).map do |l|
        sha, subject, ago, author = l.split("\t", 4)
        { sha: sha, subject: subject, ago: ago, author: author }
      end
    end

    def status
      branch = current_branch
      ahead, behind = ahead_behind

      {
        branch:   branch,
        on_vibe:  branch == Vibe.branch,
        target:   Vibe.branch,
        main:     Vibe.main,
        dirty:    changes,
        ahead:    ahead,
        behind:   behind,
        upstream: upstream?,
        log:      log(15),
      }
    end

    # unified patch for one path, or for the whole tree; untracked files are
    # diffed against /dev/null so they show as all-added
    def diff path = nil
      if path
        tracked = git?('ls-files', '--error-unmatch', '--', path).first
        return git('diff', 'HEAD', '--', path) if tracked

        # exit code 1 = files differ, the expected outcome here
        git?('diff', '--no-index', '--', '/dev/null', path).last.to_s
      else
        parts = [git('diff', 'HEAD')]
        lines(git('ls-files', '--others', '--exclude-standard')).each do |p|
          parts << git?('diff', '--no-index', '--', '/dev/null', p).last.to_s
        end
        parts.reject(&:empty?).join("\n")
      end
    end

    # --- writes (all on Vibe.branch) ---------------------------------------

    def commit message
      ensure_branch!
      message = message.to_s.strip
      raise Error, 'Commit message is empty' if message.empty?

      git 'add', '-A'
      staged = lines(git('diff', '--cached', '--name-only'))
      raise Error, 'Nothing to commit - working tree is clean' if staged.empty?

      git 'commit', '-q', '-m', message

      { sha: git('rev-parse', '--short', 'HEAD'), subject: git('log', '-1', '--format=%s'), files: staged }
    end

    # Push; if origin moved on, rebase our commits onto it and push again. The
    # commits are already safe locally, so a rebase that stops on a conflict is
    # aborted and reported rather than left half applied.
    def push
      ensure_branch!
      ok, out = push_to_origin
      return { pushed: true, incoming: [], sha: head } if ok

      fok, fout = git? 'fetch', 'origin', Vibe.branch
      raise Error, 'Push rejected and origin unreachable: %s' % Vibe.first_line(fout) unless fok

      incoming = lines(git('log', '--format=%h %s', 'HEAD..FETCH_HEAD'))

      rok, rout = git? 'rebase', 'FETCH_HEAD'
      unless rok
        git? 'rebase', '--abort'
        raise Error, 'origin/%s has new commits that conflict with yours - resolve by hand: %s' % [Vibe.branch, Vibe.first_line(rout)]
      end

      ok, out = push_to_origin
      raise Error, 'Rebased onto origin/%s but the push still failed: %s' % [Vibe.branch, Vibe.first_line(out)] unless ok

      { pushed: true, incoming: incoming, sha: head }
    end

    def push_to_origin
      git? 'push', '-u', 'origin', Vibe.branch
    end

    def pull
      ensure_branch!
      dirty = changes
      raise Error, 'Commit or discard %d local change(s) before pulling' % dirty.length if dirty.any?

      before = head
      ok, out = git? 'pull', '--rebase', 'origin', Vibe.branch
      unless ok
        git? 'rebase', '--abort'
        raise Error, 'Pull failed: %s' % Vibe.first_line(out)
      end

      { sha: head, changed: before != head, incoming: lines(git('log', '--format=%h %s', "#{before}..HEAD")) }
    end

    # main -> vibe only. The other direction is a code review, not a button.
    def merge_main
      ensure_branch!
      dirty = changes
      raise Error, 'Commit or discard %d local change(s) before merging %s' % [dirty.length, Vibe.main] if dirty.any?

      fok, _ = git? 'fetch', 'origin', Vibe.main
      source = fok ? "origin/#{Vibe.main}" : Vibe.main
      raise Error, 'No %s branch to merge from' % Vibe.main unless fok || branch_exists?(Vibe.main)

      before = head
      ok, out = git? 'merge', '--no-edit', source
      unless ok
        conflicts = lines(git?('diff', '--name-only', '--diff-filter=U').last)
        git? 'merge', '--abort'
        raise Error, 'Merging %s conflicts in: %s' % [source, conflicts.any? ? conflicts.join(', ') : Vibe.first_line(out)]
      end

      { sha: head, source: source, changed: before != head, incoming: lines(git('log', '--format=%h %s', "#{before}..HEAD")) }
    end

    # throw away every uncommitted change; ignored paths (tmp, node_modules) stay
    def reset!
      ensure_branch!
      discarded = changes
      raise Error, 'Nothing to discard - working tree is clean' if discarded.empty?

      git 'reset', '--hard', '-q'
      git 'clean', '-fd', '-q'

      { discarded: discarded.map { |c| c[:path] }, sha: head }
    end

    def discard_file path
      ensure_branch!
      path = path.to_s
      raise Error, 'No path given' if path.empty?

      if git?('ls-files', '--error-unmatch', '--', path).first
        git 'checkout', 'HEAD', '--', path
      else
        git 'clean', '-f', '-q', '--', path
      end

      { path: path }
    end

    def head
      git 'rev-parse', '--short', 'HEAD'
    end
  end
end
