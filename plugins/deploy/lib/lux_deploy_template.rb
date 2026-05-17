module LuxDeploy
  # Stupid {{VAR}} substitution. No conditionals, no loops, no escaping.
  # Missing variables raise so we never silently ship a template with
  # an un-rendered placeholder.
  module Template
    module_function

    PLACEHOLDER = /\{\{([A-Z][A-Z0-9_]*)\}\}/

    def render(str, vars)
      norm = vars.transform_keys(&:to_s)
      str.gsub(PLACEHOLDER) do
        key = ::Regexp.last_match(1)
        norm.key?(key) ? norm[key].to_s : raise(Error.new("missing var {{#{key}}}"))
      end
    end

    # Parse a rendered .env file into a symbol-keyed hash. Comments and
    # blank lines are ignored; surrounding single/double quotes are stripped.
    def parse_env(rendered)
      rendered.lines.each_with_object({}) do |line, h|
        next if line.match?(/\A\s*(#|$)/)
        k, v = line.strip.split('=', 2)
        next unless k && v
        h[k.to_sym] = v.gsub(/\A["']|["']\z/, '')
      end
    end

    # Git-derived placeholders, computed locally before any rendering.
    def git_vars
      branch = `git rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
      raise Error.new('not in a git repo (no current branch)') if branch.empty?
      {
        GIT_BRANCH:            branch,
        GIT_BRANCH_UNDERSCORE: branch.gsub(/[^A-Za-z0-9]+/, '_')
      }
    end
  end
end
