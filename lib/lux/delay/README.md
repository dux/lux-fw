## Lux.delay (Lux::DelayedJob)

Simplified access to range of delayed job operations

In default mode when you pass a block, it will execute it new Thread, but in the same context it previously was.

```ruby
Lux.delay do
  UserMailer.wellcome(@user).deliver
end
```