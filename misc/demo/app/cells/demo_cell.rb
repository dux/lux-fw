class DemoCell < ViewCell

  def time
    Time.now
  end

  def render time
    @time = time.to_i
    template :demo
  end

end