Lux.app do
  routes do
    if request.path == '/autoreload-check'
      if params[:f]
        out = {}
        for el in params[:f].split(',')
          out[el] = Digest::SHA1.hexdigest(File.read('./public/assets/%s' % el))[0,12]
        end
        response.body out
      else
        response.content_type = :js

        if Lux.dev?
          response.body Lux.fw_root.join('plugins/assets/auto_reload.js').read
        else
          response.body "console.log('Autoreload is only available in development')"
        end
      end
    end
  end
end