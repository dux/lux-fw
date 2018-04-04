## Lux::Current

### class methods

* call(*args) - flatten args and call new.call

* mock - define instance metods without logic
  ```
  mock :index, :show

  def index
  end

  def show
  end
  ```
* action

* cell

### instance methods

#### call(*args)

takes args and routes call to some other action


#### action(:name, *args)

renders action to browser


#### cell(:name, *args)

renders action withut template, overrides render info in action


#### render text:'abc', html:'</>', json:{}


#### render_part - render only template with without layout, using instance variables


#### render_to_string - same as render set_page_body:false


#### send_file - sends file to browser