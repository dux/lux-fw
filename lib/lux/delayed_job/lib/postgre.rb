# with _u as (select id from users order by updated_at asc limit 1)
# update users set updated_at=now() where id in (select id from _u) RETURNING id;

module Lux::DelayedJob::Postgre

end
