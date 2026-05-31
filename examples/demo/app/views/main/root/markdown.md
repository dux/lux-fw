# Markdown view demo

This page is a plain `.md` file under `app/views/main/root/markdown.md`,
rendered server-side through Tilt's CommonMarker adapter.

## What works

* CommonMark / GitHub-flavored Markdown
* Lists, **bold**, _italic_, `inline code`
* Links: [lux-fw](https://github.com/dux/lux-fw)

```ruby
# fenced code blocks render too
def hello
  'world'
end
```

> Note: the Markdown is static - it does not evaluate Haml/ERB or call
> helpers. Keep dynamic bits in the layout.
