# Restarting the app the harness is editing.
#
# soft - touch tmp/restart.txt: puma's tmp_restart plugin (enabled by lux_boot,
#        lib/lux/boot/puma.rb) reloads the Ruby side in about a second. Enough
#        for .rb/.haml/route changes; JS/CSS are rebuilt by the rollup watcher.
# hard - `docker restart` of the app container through the docker socket, for
#        Gemfile/package.json changes that need a full boot. The socket is only
#        mounted into the vibe container, never where the agent runs shell.

module Vibe
  module Restart
    TRIGGER ||= 'tmp/restart.txt'

    module_function

    def soft
      path = File.join(Vibe.root, TRIGGER)
      FileUtils.mkdir_p File.dirname(path)
      File.write path, Time.now.to_s
      { mode: 'soft', trigger: TRIGGER }
    end

    def hard
      if docker_socket?
        id = app_container_id
        raise Error, 'No running "%s" container in compose project "%s"' % [Vibe.app_service, Vibe.compose_project] unless id

        Vibe.run! 'docker', 'restart', id, timeout: 180
        { mode: 'hard', container: id }
      elsif (file = Vibe.compose_file)
        # on the host: no socket needed, compose knows the project
        Vibe.run! 'docker', 'compose', '--project-directory', Vibe.root, '-f', file, 'restart', Vibe.app_service, timeout: 180
        { mode: 'hard', service: Vibe.app_service }
      else
        raise Error, 'Hard restart needs the docker socket (/var/run/docker.sock) or a config/docker/docker-compose.yml in %s' % Vibe.root
      end
    end

    def docker_socket?
      File.exist?('/var/run/docker.sock') && docker_cli?
    end

    def docker_cli?
      Vibe.run('docker', '--version', timeout: 5).first
    end

    def app_container_id
      ok, out = Vibe.run('docker', 'ps', '-q',
        '--filter', "label=com.docker.compose.project=#{Vibe.compose_project}",
        '--filter', "label=com.docker.compose.service=#{Vibe.app_service}", timeout: 10)
      return nil unless ok

      Vibe.first_line(out).then { |s| s.empty? ? nil : s }
    end

    # last lines of the app container's stdout (the compose log for `app`)
    def container_logs tail: 200
      raise Error, 'docker socket not available' unless docker_socket?

      id = app_container_id
      raise Error, 'app container not running' unless id

      Vibe.run('docker', 'logs', '--tail', tail.to_s, id, timeout: 15).last
    end
  end
end
