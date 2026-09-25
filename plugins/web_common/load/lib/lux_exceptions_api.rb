class LuxExceptionsApi < ApplicationApi
  before do
    user.can.admin!
  end

  define :toggle do
    desc 'Flip is_resolved on one exception group'
    params do
      uid String, max: 100
    end
    proc do
      exp = LuxException.first(uid: @api.params[:uid]) or error('Exception not found')
      exp.update is_resolved: !exp.is_resolved
      { is_resolved: exp.is_resolved }
    end
  end
end
