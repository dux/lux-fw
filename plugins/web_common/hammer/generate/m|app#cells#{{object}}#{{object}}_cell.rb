class {{klass}}Cell < ViewCell
  before do
  end

  def part {{object}}
    @{{object}} = {{object}}
    template :part
  end
end
