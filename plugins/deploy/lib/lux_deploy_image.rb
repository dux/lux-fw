module LuxDeploy
  # Local image build + archive flow. Produces tmp/deploy/<app>/images.tar.gz
  # containing the configured images. The archive is the deploy artifact.
  module Image
    module_function

    def archive_dir(config)
      File.join(config[:app_root], 'tmp', 'deploy', config[:app])
    end

    def archive_path(config)
      File.join(archive_dir(config), 'images.tar.gz')
    end

    def image_refs(config)
      config[:images].values
    end

    def build!(config)
      FileUtils.mkdir_p(archive_dir(config))
      env_file = write_build_env(config)
      argv = Compose.local_argv(config, env_file: env_file)
      LuxDeploy.run_local!("#{argv.map { |s| LuxDeploy.sh(s) }.join(' ')} config -q",
                           quiet: config[:quiet])
      LuxDeploy.run_local!("#{argv.map { |s| LuxDeploy.sh(s) }.join(' ')} build",
                           quiet: config[:quiet])
      tag_local_images!(config)
      save_archive!(config)
    end

    # Tag built images to the configured names so docker save picks them up
    # under their deployable refs even if the Dockerfile produced a default
    # `lux-<svc>:latest` style image name.
    def tag_local_images!(config)
      # Compose tags built images as `<project>-<service>` by default. Rename
      # those to the configured `images.<name>` value.
      config[:images].each do |svc, ref|
        from = "#{config[:compose_project]}-#{svc}"
        LuxDeploy.run_local("docker tag #{LuxDeploy.sh(from)} #{LuxDeploy.sh(ref)}",
                            quiet: config[:quiet])
      end
    end

    def save_archive!(config)
      refs = image_refs(config).map { |r| LuxDeploy.sh(r) }.join(' ')
      out = archive_path(config)
      LuxDeploy.run_local!("docker save #{refs} | gzip > #{LuxDeploy.sh(out)}",
                           quiet: config[:quiet])
      out
    end

    # Compose needs both image refs (so `up --no-build` finds the build outputs)
    # and host paths. For local build we only need image refs.
    def write_build_env(config)
      lines = []
      config[:images].each do |svc, ref|
        lines << "#{svc.to_s.upcase}_IMAGE=#{ref}"
      end
      path = File.join(archive_dir(config), 'build.env')
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, lines.join("\n") + "\n")
      path
    end

    def upload!(ctx)
      local = archive_path(ctx.config)
      unless File.file?(local)
        raise Error.new(
          'image archive missing',
          expected: "#{local} exists",
          current: 'no archive built',
          need: 'run lux deploy:build (or deploy --build) first',
          fix: "lux deploy:build #{ctx.config[:profile]}",
          category: :preflight
        )
      end
      remote = "#{ctx.path}/config/docker/images.tar.gz"
      ctx.ssh.scp!(local, remote, category: :source)
      remote
    end

    def remote_load!(ctx)
      remote = "#{ctx.path}/config/docker/images.tar.gz"
      ctx.ssh.ssh!("gunzip -c #{LuxDeploy.sh(remote)} | docker load",
                   category: :source, summary: 'docker load failed on host')
    end

    # Locally load the archive (used by deploy:test when images are missing).
    def local_load!(config)
      path = archive_path(config)
      LuxDeploy.run_local!("gunzip -c #{LuxDeploy.sh(path)} | docker load",
                           quiet: config[:quiet])
    end

    def local_images_present?(config)
      image_refs(config).all? do |ref|
        result = LuxDeploy.run_local("docker image inspect #{LuxDeploy.sh(ref)} >/dev/null 2>&1",
                                     quiet: true)
        result.success?
      end
    end
  end
end
