# CDN upload contract every lux app can fulfill:
#
#   lux assets:upload LOCAL_PATH REMOTE_PATH
#
# LOCAL_PATH is a local file. REMOTE_PATH is relative to what cdn_root serves;
# a trailing / makes it a folder and the file keeps its basename. Failure must
# exit non-zero (Lux.shell.die) so callers like assets:deploy abort.
#
# An app with a CDN overrides this task in lib/tasks (app tasks load last) and
# owns how it authenticates - ENV, secrets, SDK or CLI. Without an override
# nothing is uploaded: lux pack ships public/assets and they are served from
# the app's own /assets path.
namespace :assets do
  task :upload do
    desc 'Upload LOCAL_PATH to REMOTE_PATH on the app CDN (app defines it in lib/tasks)'

    proc do |opts|
      local = opts[:args].first
      Lux.shell.info "assets:upload is not defined for a CDN in this app, #{local || 'assets'} is served from the local /assets path"
    end
  end
end
