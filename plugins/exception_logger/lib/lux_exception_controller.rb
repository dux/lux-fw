# POST endpoints for the exception_logger admin pages. The GET pages (list +
# show) are pure templates rendered by the host's AdminController via
# auto_find_template - they live at app/views/admin/plugins/exception_logger/
# and look up their own data, so no controller action is needed for them.
#
# Required from the plugin loader so the per-action `route` annotation
# registers at boot, independent of host controller autoloading.

class LuxExceptionController < Lux::Controller
  route '/admin/plugins/exception_logger/resolve'
  allow :post
  def resolve
    exep = LuxException.first(uid: params[:uid]) or Lux.error.not_found
    exep.update is_resolved: true
    redirect_to '/admin/plugins/exception_logger/show?uid=%s' % exep.uid
  end
end
