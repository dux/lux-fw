class LuxJobsApi < ModelApi
  # documented

  # generate :show
  # generate :create
  # generate :update
  # generate :destroy

  member do
    before do
      user.can.admin!
    end

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
