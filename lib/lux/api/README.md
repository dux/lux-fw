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


### Response decorator

```
class ApplicationApi < Lux::Api

  # called at the end of response
  def decorate_response!(data=nil)
    @response = data if data
    @response[:ip] = Lux.current.request.ip
    @response[:user] = Lux.current.var.user ? Lux.current.var.user.email : false
    @response[:http_status] = Lux.current.response.status(200)
    @response[:error] ||= 'Bad request' if Lux.current.response.status != 200
    @response
  end

  def after
    decorate_response!
  end

end
```

### Rescues

Default rescue handler, can be owerriden

```
Lux::Api.class_eval do
  rescue_from(:all) do |msg|
    data =  { error:msg }

    if Lux.dev? && $!.class != StandardError
      data[:backtrace] = $!.backtrace.reject{ |el| el.index('/gems/') }.map{ |el| el.sub(Lux.root.to_s, '') }
    end

    Lux.current.response.body ApplicationApi.decorate_response(data)
 end
end
```