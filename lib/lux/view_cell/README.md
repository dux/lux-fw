## Lux::ViewCell

View cells a partial view-part/render/controllers combo.

Idea is to have idempotent cell render metod, that can be reused in may places.
You can think of view cells as rails `render_partial` with localized controller attached.

```ruby
class CityCell < ViewCell

  # template_root './apps/cities/cells/views/cities'

  before do
    @skill = parent { @skill }
  end

  ###

  def skills
    @city
      .jobs
      .skills[0,3]
      .map{ |it| it[:name].wrap(:span, class: 'skill' ) }
      .join(' ')
  end

  def render city
    @city    = city
    @country = city.country

    template :city
  end
end
```

And call them in templates like this

```ruby
cell.city.skills
cell.city.render @city
```