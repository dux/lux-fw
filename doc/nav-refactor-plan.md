<user_edit>
# Nav refactor plan

> STATUS: proposal, nothing implemented. Facts and open decisions only.

Goal: replace the `:ref` placeholder symbol with a typed path segment that carries its own value,
under

./lib/lux/application/lib/nav/base.rb -> basic contract interface
./lib/lux/application/lib/nav/string.rb -> ref implentation we have in plugin now

* we will move full public interface to ref wors on nav.ref -> it will be method that
nav.ref.filter -> should be in /Users/dux/dev/gems/lux-fw/lib/lux/application/lib/nav/base.rb
nav.ref.filter(:string, { upcase: true }) -> maps path to ref objects -> this is only line I want to have in routes
nav.ref.filter(:string, { upcase: true }) do |current_path_list, matched_el|
  # if block given, and I return false, use original value. for rare cases we want
end

{ upcase: true } -> this are attributes to pass when we create instance of object. for exaple type of ulid, uuid, etc.

ref object in path is instance of Ref, to_s returns original value. it has methods validate -> true | false

</user_edit>

