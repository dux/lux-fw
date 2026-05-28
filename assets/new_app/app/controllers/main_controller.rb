class MainController < ApplicationController
  def root
    @user = user
  end

  def logout
    session.delete(:user_ref)
    redirect_to '/', info: 'Signed out'
  end
end
