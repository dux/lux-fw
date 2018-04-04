## Lux::Helper

Lux Helpers provide easy way to group common functions.

* helpers shud be in app/helpers folder
* same as Rails helpers
* called by Lux::Template before rendering any view


### Example

for this to work

```Lux::Helper.for(:rails, instance_vars={}).link_to(...)```

RailsHelper module has to define link_to method

