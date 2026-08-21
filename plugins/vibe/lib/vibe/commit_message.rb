# "Auto message" for the commit box: one OpenRouter chat completion over the
# staged diff. Uses the same OPENROUTER_API_KEY as the agent, a small/cheap
# model by default. Falls back to a plain "vibe: update N files" line when
# there is no key or the request fails - a commit must never block on this.

require 'net/http'

module Vibe
  module CommitMessage
    ENDPOINT   ||= 'https://openrouter.ai/api/v1/chat/completions'
    MAX_DIFF   ||= 12_000
    DEFAULT    ||= 'anthropic/claude-haiku-4.5'

    module_function

    def model
      ENV['VIBE_COMMIT_MODEL'] || DEFAULT
    end

    # Stages everything first so the diff describes exactly what `commit` will
    # record; returns the message text.
    def generate
      Git.git 'add', '-A'
      stat  = Git.git('diff', '--cached', '--stat')
      files = Git.lines(Git.git('diff', '--cached', '--name-only'))
      raise Error, 'Nothing to describe - working tree is clean' if files.empty?

      diff = Git.git('diff', '--cached')
      diff = diff[0, MAX_DIFF] + "\n... (diff truncated)" if diff.length > MAX_DIFF

      llm(stat, diff) || fallback(files)
    end

    def fallback files
      names = files.map { |f| File.basename(f) }
      list  = names.first(3).join(', ')
      list += ' +%d' % (names.length - 3) if names.length > 3
      'vibe: update %d file%s (%s)' % [files.length, files.length == 1 ? '' : 's', list]
    end

    def llm stat, diff
      key = Vibe.openrouter_key
      return nil if key.empty?

      prompt = <<~TXT
        Write a git commit message for the staged diff below.
        Rules: first line is an imperative subject of at most 72 characters, optionally
        prefixed with the area it touches (e.g. "invoices: ..."); then, only if the change
        is not obvious from the subject, a blank line and one to three short plain lines
        saying what changed and why. No markdown, no quotes, no trailing period on the subject.
        Answer with the commit message only.

        --- stat ---
        #{stat}

        --- diff ---
        #{diff}
      TXT

      req = Net::HTTP::Post.new(URI(ENDPOINT))
      req['authorization'] = "Bearer #{key}"
      req['content-type']  = 'application/json'
      req['x-title']       = 'lux vibe'
      req.body = JSON.generate(
        model: model,
        max_tokens: 200,
        temperature: 0.2,
        messages: [{ role: 'user', content: prompt }]
      )

      uri = req.uri
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 30) { |h| h.request(req) }
      return nil unless res.is_a?(Net::HTTPSuccess)

      text = JSON.parse(res.body).dig('choices', 0, 'message', 'content').to_s
      clean(text)
    rescue StandardError
      nil
    end

    def clean text
      text = text.strip.gsub(/\A```\w*\n?|```\z/, '').strip
      return nil if text.empty?

      lines = text.lines.map(&:rstrip)
      lines[0] = lines[0].sub(/\.\z/, '')[0, 72]
      lines.join("\n").strip
    end
  end
end
