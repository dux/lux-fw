# Lux::View - template based rendering helpers

## Tempalte render flow

* Lux::View.render_with_layout('main/users/show', { :@user=>User.find(1) })
* Lux::View.render_part('main/users/show', { :@user=>User.find(1) })
* helper runtime context is prepared by Lux::View::Helper.for('main')
* templte 'main/users/show' is renderd with options
* layout template 'main/layout' is renderd and previous render result is injected via yield

## Lux::View - Calling templates

* all templates are in app/views folder
* you can call template with Lux::View.render_with_layout(template, opts={}) or Lux::View.render_part(template, opts={})
* Lux::View.render_with_layput renders template with layout
* Lux::View.render_part renders without layout


### Inline render

```
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

## ViewCell

View components in rails

Define them like this

```
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

```
cell.city.skills
cell.city.render @city
```