class LuxJobsApi < ModelApi
  # Admin-only across the board; leans on the host's authorization.
  before do
    user.can.admin!
  end

  define :trigger do
    desc 'Enqueue a defined job to run now'
    params do
      name String, max: 100
      opts? Hash, default: {}
    end
    proc do
      job_key = @api.params[:name].to_sym
      @api.error "Job '#{@api.params[:name]}' not defined", status: 404 unless LuxJob::JOBS[job_key]

      job = LuxJob.add(job_key, @api.params[:opts] || {})
      { ok: true, ref: job.ref, name: @api.params[:name] }
    end
  end

  define :poll do
    desc 'Return last log timestamp; clients poll this and refresh the page when it changes'
    params do
      name? String
    end
    proc do
      { last_id: LuxJob.last_log_id(name: @api.params[:name]) }
    end
  end

  define :log do
    desc 'Recent log lines, newest first (for the dashboard log tail)'
    params do
      name?  String
      lines? Integer
    end
    proc do
      { lines: LuxJob.tail_log(name: @api.params[:name], lines: @api.params[:lines] || 100) }
    end
  end

  # Runs go through the runner, never a web thread: only the runner holds the
  # advisory lock that keeps a job from running twice.
  ref do
    define :restart do
      proc do
        @lux_job.this.update run_at: Time.now, status_sid: 's', retry_count: 0
        LuxJob.notify_listeners
        'Scheduled to run now'
      end
    end
  end
end
