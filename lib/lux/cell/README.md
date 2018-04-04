## Lux::Cell - Calling cells

Cells are Lux view models

* all cells shoud inherit from Lux::Cell
* before and after class methods supportd
  * you can also use before and after instance methods (better)
* rescue_from is supported
* calls temaplates

* Www::UserCell.call(:show, params[:id]) will
  * call show instance method in Www::UserCell
  * will pass instance variales to 'app/views/www/users/show'
  * and will use layout template 'app/views/www/layout.{haml,erb}'

## Class methods

### Lux::Cell.call(@path)

* Www::UserCell.call(@path)
  * /users          -> will render :index if @path.blank?
  * /user/2         -> will render :show, @path.first if @path.first.kind_of?(Integer)
  * /users/comments -> will render :comments, @path.first == :comments
  * /users/2/comments -> render :commnets, 2, @path == [2, :comments]

### Lux::Cell.action(:name, *opts)

```@cell.action(:name, *opts)```

Calls single action

```UserCell.action(:show, 1)```

### Lux::Cell.mock(:names)

Mock methods

```mock :index, :show```

### Lux::Cell.

* for use in helpers, mostly
* renders only cell without layout

= cell :method, argument





