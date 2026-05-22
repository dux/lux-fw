class LuxJobsApi < ModelApi
  # Admin-only across the board. Same gate the previous Sinatra dashboard
  # used (basic auth password); here it leans on the host's authorization.
  before do
    user.can.admin!
  end

  # generate :show
  # generate :create
  # generate :update
  # generate :destroy

  desc 'Enqueue a defined job to run now'
  params do
    name String, max: 100
    opts? Hash, default: {}
  end
  def trigger
    job_key = @api.params[:name].to_sym
    @api.error "Job '#{@api.params[:name]}' not defined", status: 404 unless LuxJob::JOBS[job_key]

    job = LuxJob.add(job_key, @api.params[:opts] || {})
    { ok: true, ref: job.ref, name: @api.params[:name] }
  end

  desc 'Return last log timestamp; clients poll this and refresh the page when it changes'
  params do
    name? String
  end
  def poll
    { last_id: LuxJob.last_log_id(name: @api.params[:name]) }
  end

  desc 'Recent log lines, newest first (for the dashboard log tail)'
  params do
    name?  String
    lines? Integer
  end
  def log
    { lines: LuxJob.tail_log(name: @api.params[:name], lines: @api.params[:lines] || 100) }
  end

  member do
    def restart
      @lux_job.this.update run_at: Time.now, status_sid: 's', retry_count: 0
      'Scheduled to run now'
    end

    def run
      Thread.new { LuxJob.run_job @lux_job }
      'Running in background'
    end
  end
end
