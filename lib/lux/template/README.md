## Tempalte render flow

* Lux::Template.render_with_layout('main/users/show', { :@user=>User.find(1) })
* Lux::Template.render_part('main/users/show', { :@user=>User.find(1) })
* helper runtime context is prepared by Lux::Helper.for('main')
* templte 'main/users/show' is renderd with options
* layout template 'main/layout' is renderd and previous render result is injected via yield

### Lux::Template - Calling templates

* all templates are in app/views folder
* you cal template with Lux::Template.render_with_layout(template, opts={}) or Lux::Template.render_part(template, opts={})
* Lux::Template.render_with_layput renders template with layout
* Lux::Template.render_part renders without layout


### Inline render

```
= render :_part, name:'Dux'
```

in `_part.haml` access option `name: ...` via instance variable `@_name`
