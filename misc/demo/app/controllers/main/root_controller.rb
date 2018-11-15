class Main::RootController < ApplicationContrller

  mock :about

  def index
    @title = 'Yay, you are on Lux'
  end

end