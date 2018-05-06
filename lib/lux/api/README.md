## Lux::Api

Default class for writing APIs

### General rules

* defines Lux::Api, ApplicationApi and ModelApi
  * ApplicationApi - defines decorator and default rescue for output messages
  * ModelApi - defines create, read, update and delete methods
    * checks every action via Policy.can?(current_user, action, model)
      ``` Policy.can?(Lux.current.var.user, :update?, @note) ```
      checks if current user can update defined model
  * you shuld modify and inherit from ApplicationApi or ModelApi

* you can use before and after filters
* attributes that are requested and checked via "param :name" are available as @_name


### Example

```
class BlogApi < ModelApi

  name  'List all blogs'
  desc  'will list all blogs'
  def index
    Blog.order(:id).select(:id, :name).page
  end

  name  'Show single blog by id'
  param :id, Integer
  def show
    Blog.find(@_id)
  end

end
```

### Rescues

Define API rescue handler

```
ApplicationApi.on_error do |e|
  key = SimpleException.log(e)
  response.meta :error_key, key
  response.meta :error_class, e.class
end
```