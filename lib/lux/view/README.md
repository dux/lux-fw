## Lux::View - Backend template helpers

Template based rendering helpers

### Template render flow

* Lux::View.render(context, 'main/users/template')
* Lux::View.render(context, 'main/users/template', 'views/layouts/main')
* Lux::View.render(context, 'views/layouts/main') { @template_data }
* context is self or any other object (Hash)
  * methods called in templates will be called from context
  * context = Lux::View::Helper.new self, :main (prepare Rails style helper)


### Inline render

```ruby
= render :_part, name: 'Foo'
```

in `_part.haml` access option `name: ...` via instance variable `@_name`


### Lux::View::Helper

Lux Helpers provide easy way to group common functions.

* helpers shud be in app/helpers folder
* same as Rails View helpers
* called by Lux::View before rendering any view


### Example

for this to work

```Lux::View::Helper.for(:rails, @instance_variables_hash).link_to(...)```

RailsHelper module has to define link_to method

### ViewCell

View components in rails

Define them like this

```ruby
class CityCell < ViewCell

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

And call them on templates like this

```ruby
cell.city.skills
cell.city.render @city
```