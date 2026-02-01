# Sinatra web interface for LuxJob
# Standalone: rake job_runner:web[password]
# Mounted in Lux: mount LuxJobWeb.mounted('/job-runner', 'password') => '/job-runner'

require 'sinatra/base'

class LuxJobWeb < Sinatra::Base
  class << self
    attr_accessor :password, :prefix

    def mounted(prefix, password)
      self.prefix = prefix
      self.password = password
      self
    end
  end

  helpers do
    def prefix
      self.class.prefix || ''
    end

    def time_ago(time)
      return '' unless time
      diff = Time.now - time
      case diff
      when 0..59 then "#{diff.to_i}s ago"
      when 60..3599 then "#{(diff / 60).to_i}m ago"
      when 3600..86399 then "#{(diff / 3600).to_i}h ago"
      else "#{(diff / 86400).to_i}d ago"
      end
    end

    def time_relative(time)
      return '' unless time
      diff = time - Time.now
      past = diff < 0
      diff = diff.abs
      val = case diff
      when 0..59 then "#{diff.to_i}s"
      when 60..3599 then "#{(diff / 60).to_i}m"
      when 3600..86399 then "#{(diff / 3600).to_i}h"
      else "#{(diff / 86400).to_i}d"
      end
      past ? "#{val} ago" : "in #{val}"
    end

    def parse_log_line(line)
      if line =~ /\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})\.\d+ #\d+\]\s+\w+ -- : (.+)/
        time = Time.parse($1) rescue nil
        { time: time, message: $2 }
      else
        { time: nil, message: line }
      end
    end
  end

  set :port, 3001
  set :bind, '0.0.0.0'
  set :protection, false
  set :host_authorization, { allow_if: ->(_env) { true } }

  class << self
    attr_accessor :password
  end

  before do
    if self.class.password
      auth = Rack::Auth::Basic::Request.new(request.env)
      unless auth.provided? && auth.basic? && auth.credentials[1] == self.class.password
        headers['WWW-Authenticate'] = 'Basic realm="LuxJob"'
        halt 401, 'Unauthorized'
      end
    end
  end

  # Routes - work with and without /job-runner prefix
  ['/job-runner', ''].each do |pfx|
    get "#{pfx}/?" do
      @jobs = LuxJob::JOBS.map do |name, opts|
        db_job = LuxJob.first(name: name.to_s)
        {
          name: name,
          every: opts[:every],
          last_run: db_job&.updated_at,
          next_run: db_job&.run_at,
          status: db_job&.status,
          response: db_job&.response
        }
      end

      @recent_runs = `tail -n 100 ./log/lux_job.log 2>/dev/null`.split("\n").reverse
      @last_id = @recent_runs.first&.match(/\[(\d{4}-\d{2}-\d{2}T[\d:\.]+)/)[1] rescue nil

      erb :index
    end

    get "#{pfx}/job/:name" do
      @name = params[:name]
      @job_info = LuxJob::JOBS[@name.to_sym]
      halt 404, "Job not found" unless @job_info

      @db_job = LuxJob.first(name: @name)
      @log_lines = `grep -i '\\[#{@name}\\]' ./log/lux_job.log 2>/dev/null | tail -n 1000`.split("\n").reverse
      @last_id = @log_lines.first&.match(/\[(\d{4}-\d{2}-\d{2}T[\d:\.]+)/)[1] rescue nil

      erb :job
    end

    get "#{pfx}/poll" do
      content_type :json
      job_name = params[:job].to_s.empty? ? nil : params[:job]

      last_line = if job_name
        `grep -i '\\[#{job_name}\\]' ./log/lux_job.log 2>/dev/null | tail -n 1`.strip
      else
        `tail -n 1 ./log/lux_job.log 2>/dev/null`.strip
      end

      last_id = last_line.match(/\[(\d{4}-\d{2}-\d{2}T[\d:\.]+)/)[1] rescue nil
      changed = params[:last_id].to_s.empty? || last_id != params[:last_id]

      { changed: changed, last_id: last_id }.to_json
    end

    get "#{pfx}/log/:job_name" do
      content_type 'text/plain'
      `grep -i '\\[#{params[:job_name]}\\]' ./log/lux_job.log 2>/dev/null | tail -n 10000`
    end

    # POST /job/:name - trigger job with JSON payload
    post "#{pfx}/job/:name" do
      content_type :json
      name = params[:name]

      unless LuxJob::JOBS[name.to_sym]
        halt 404, { error: "Job '#{name}' not found" }.to_json
      end

      opts = {}
      if request.content_type&.include?('application/json') && request.body.size > 0
        request.body.rewind
        opts = JSON.parse(request.body.read, symbolize_names: true) rescue {}
      end

      job = LuxJob.add(name, opts)
      { ok: true, job_id: job.id, name: name, opts: opts }.to_json
    end
  end

  template :layout do
    <<~HTML
      <!DOCTYPE html>
      <html>
      <head>
        <title>LuxJob Dashboard</title>
        <style>
          * { box-sizing: border-box; }
          body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            margin: 0;
            padding: 20px;
            background: #f5f5f5;
          }
          h1 { margin: 0 0 20px; color: #333; }
          h2 { margin: 20px 0 10px; color: #555; }
          a { color: #0066cc; text-decoration: none; }
          a:hover { text-decoration: underline; }
          .container { max-width: 1200px; margin: 0 auto; }
          table {
            width: 100%;
            border-collapse: collapse;
            background: white;
            box-shadow: 0 1px 3px rgba(0,0,0,0.1);
            margin-bottom: 20px;
          }
          th, td {
            padding: 12px;
            text-align: left;
            border-bottom: 1px solid #eee;
          }
          th { background: #f8f8f8; font-weight: 600; }
          tr:hover { background: #fafafa; }
          .status-Done { color: #28a745; }
          .status-Running { color: #007bff; }
          .status-Failed { color: #dc3545; }
          .status-Scheduled { color: #6c757d; }
          .log-box {
            background: #1e1e1e;
            color: #d4d4d4;
            padding: 15px;
            font-family: monospace;
            font-size: 13px;
            overflow-x: auto;
            max-height: 1500px;
            overflow-y: auto;
            border-radius: 4px;
          }
          .log-box .line { padding: 2px 0; white-space: pre; }
          .log-box .error { color: #f48771; }
          .back { margin-bottom: 15px; display: inline-block; }
          .add-job { margin-top: 20px; padding: 15px; background: white; border-radius: 4px; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
          .add-job h3 { margin: 0 0 10px; }
          .add-job textarea { width: 100%; height: 80px; font-family: monospace; padding: 8px; border: 1px solid #ddd; border-radius: 4px; }
          .add-job button { margin-top: 10px; padding: 8px 16px; background: #0066cc; color: white; border: none; border-radius: 4px; cursor: pointer; }
          .add-job button:hover { background: #0052a3; }
          .add-job .result { margin-top: 10px; padding: 10px; border-radius: 4px; }
          .add-job .result.success { background: #d4edda; color: #155724; }
          .add-job .result.error { background: #f8d7da; color: #721c24; }
          .log-box .time { color: #888; }
        </style>
      </head>
      <body>
        <div class="container">
          <%= yield %>
        </div>
        <script src="https://unpkg.com/idiomorph@0.3.0/dist/idiomorph.min.js"></script>
        <script>
          (function() {
            const logBox = document.getElementById('log-box');
            if (!logBox) return;

            let lastId = logBox.dataset.lastId || '';
            const job = logBox.dataset.job || '';
            const prefix = window.location.pathname.includes('/job-runner') ? '/job-runner' : '';

            setInterval(async () => {
              const url = prefix + '/poll?last_id=' + encodeURIComponent(lastId) + (job ? '&job=' + job : '');
              try {
                const resp = await fetch(url, { credentials: 'same-origin' });
                const data = await resp.json();
                if (data.changed) {
                  const pageResp = await fetch(window.location.href, { credentials: 'same-origin' });
                  const html = await pageResp.text();
                  const parser = new DOMParser();
                  const doc = parser.parseFromString(html, 'text/html');
                  Idiomorph.morph(document.querySelector('.container'), doc.querySelector('.container'));
                  lastId = data.last_id || '';
                }
              } catch (e) { console.error('Poll error:', e, resp?.status); }
            }, 3000);
          })();
        </script>
      </body>
      </html>
    HTML
  end

  template :index do
    <<~HTML
      <h1>LuxJob Dashboard</h1>

      <h2>Registered Jobs</h2>
      <table>
        <tr>
          <th>Name</th>
          <th>Schedule</th>
          <th>Last Run</th>
          <th>Next Run</th>
          <th>Status</th>
          <th>Response</th>
        </tr>
        <% @jobs.each do |job| %>
          <tr>
            <td><a href="<%= prefix %>/job/<%= job[:name] %>"><%= job[:name] %></a></td>
            <td>
              <% if job[:every] %>
                every <%= job[:every].parts.map { |u, v| "\#{v} \#{u}" }.join(', ') %>
              <% else %>
                on demand
              <% end %>
            </td>
            <td><% if job[:last_run] %><%= job[:last_run].strftime('%Y-%m-%d %H:%M:%S') %> (<%= time_relative(job[:last_run]) %>)<% else %>-<% end %></td>
            <td><% if job[:next_run] %><%= job[:next_run].strftime('%Y-%m-%d %H:%M:%S') %> (<%= time_relative(job[:next_run]) %>)<% else %>-<% end %></td>
            <td class="status-<%= job[:status] %>"><%= job[:status] || '-' %></td>
            <td><%= job[:response] ? job[:response][0, 50] : '-' %></td>
          </tr>
        <% end %>
      </table>

      <h2>Recent Log (last 100 entries)</h2>
      <div class="log-box" id="log-box" data-last-id="<%= @last_id %>" data-job="">
        <% @recent_runs.each do |line| %>
          <% parsed = parse_log_line(line) %>
          <div class="line<%= ' error' if line.include?('ERROR') %>"><span class="time"><%= time_ago(parsed[:time]) %></span> <%= parsed[:message] %></div>
        <% end %>
        <% if @recent_runs.empty? %>
          <div class="line">No log entries yet</div>
        <% end %>
      </div>
    HTML
  end

  template :job do
    <<~HTML
      <a href="<%= prefix %>/" class="back">&larr; Back to Dashboard</a>
      <h1>Job: <%= @name %></h1>

      <table>
        <tr>
          <th>Schedule</th>
          <td>
            <% if @job_info[:every] %>
              every <%= @job_info[:every].parts.map { |u, v| "\#{v} \#{u}" }.join(', ') %>
            <% else %>
              on demand
            <% end %>
          </td>
        </tr>
        <% if @db_job %>
          <tr><th>Status</th><td class="status-<%= @db_job.status %>"><%= @db_job.status %></td></tr>
          <tr><th>Last Run</th><td><% if @db_job.updated_at %><%= @db_job.updated_at.strftime('%Y-%m-%d %H:%M:%S') %> (<%= time_relative(@db_job.updated_at) %>)<% else %>-<% end %></td></tr>
          <tr><th>Next Run</th><td><% if @db_job.run_at %><%= @db_job.run_at.strftime('%Y-%m-%d %H:%M:%S') %> (<%= time_relative(@db_job.run_at) %>)<% else %>-<% end %></td></tr>
          <tr><th>Response</th><td><%= @db_job.response %></td></tr>
          <tr><th>Retry Count</th><td><%= @db_job.retry_count %></td></tr>
        <% else %>
          <tr><td colspan="2">No database record (job not yet initialized)</td></tr>
        <% end %>
      </table>

      <div class="add-job">
        <h3>Add Job to Queue</h3>
        <textarea id="payload" placeholder='{"key": "value"} or leave empty'></textarea>
        <button onclick="addJob()">Add Job</button>
        <div id="result"></div>
      </div>

      <script>
        async function addJob() {
          const payload = document.getElementById('payload').value.trim();
          const result = document.getElementById('result');
          let body = null;

          if (payload) {
            try {
              JSON.parse(payload);
              body = payload;
            } catch (e) {
              result.className = 'result error';
              result.textContent = 'Invalid JSON: ' + e.message;
              return;
            }
          }

          try {
            const resp = await fetch('<%= prefix %>/job/<%= @name %>', {
              method: 'POST',
              headers: body ? {'Content-Type': 'application/json'} : {},
              body: body
            });
            const data = await resp.json();
            if (data.ok) {
              result.className = 'result success';
              result.textContent = 'Job added: ' + data.job_id;
            } else {
              result.className = 'result error';
              result.textContent = 'Error: ' + (data.error || 'Unknown error');
            }
          } catch (e) {
            result.className = 'result error';
            result.textContent = 'Request failed: ' + e.message;
          }
        }
      </script>

      <h2><a href="<%= prefix %>/log/<%= @name %>" target="_blank" style="color: inherit;">Log (last 1000 entries)</a></h2>
      <div class="log-box" id="log-box" data-last-id="<%= @last_id %>" data-job="<%= @name %>">
        <% @log_lines.each do |line| %>
          <% parsed = parse_log_line(line) %>
          <div class="line<%= ' error' if line.include?('ERROR') %>"><span class="time"><%= time_ago(parsed[:time]) %></span> <%= parsed[:message] %></div>
        <% end %>
        <% if @log_lines.empty? %>
          <div class="line">No log entries for this job</div>
        <% end %>
      </div>
    HTML
  end
end
