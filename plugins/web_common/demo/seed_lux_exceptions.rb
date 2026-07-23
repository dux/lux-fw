# Seed LuxException / LuxExceptionLog with 100 random fake exceptions for
# admin plugin UI testing. Writes directly via the models so timestamps,
# times, is_resolved and log spread can be controlled.
#
# NOT auto-loaded by `lux db:seed` (lives under demo/, not seeds/).
# Load manually when you want demo exception UI data:
#   bundle exec lux e 'load Lux.fw_root.join("plugins/web_common/demo/seed_lux_exceptions.rb").to_s'

require 'digest'

ERR_CLASSES ||= %w[
  NoMethodError ArgumentError RuntimeError NameError TypeError
  ZeroDivisionError KeyError IOError NotImplementedError RangeError
  Sequel::DatabaseError Sequel::NoMatchingRow Net::ReadTimeout
  JSON::ParserError Encoding::UndefinedConversionError SystemCallError
  Errno::ECONNRESET Errno::ETIMEDOUT Stripe::CardError
]

MSG_TEMPLATES ||= [
  "undefined method `%s' for nil:NilClass",
  "wrong number of arguments (given %d, expected %d)",
  "uninitialized constant %s",
  "no implicit conversion of nil into %s",
  "comparison of %s with nil failed",
  "divided by 0",
  "key not found: :%s",
  "PG::UniqueViolation: duplicate key value violates unique constraint \"%s_pkey\"",
  "Net::ReadTimeout with #<TCPSocket:(closed)>",
  "Connection refused - connect(2) for \"%s\" port 443",
  "stack level too deep",
  "Your card was declined.",
  "JSON::ParserError: unexpected token at '<html>'",
  "ENOENT: No such file or directory @ rb_sysopen - %s",
  "Translation missing: en.errors.%s",
]

METHOD_NAMES ||= %w[
  call run save update! create perform fetch render to_h sync
  resolve commit apply handle process publish notify dispatch
]

CLASS_NAMES ||= %w[
  Board Task User Space Note Message Contact Org
  ApplicationRecord PaymentProfile WebhookHandler InboundEmail
]

FILES ||= %w[
  app/controllers/main_controller.rb
  app/controllers/admin_controller.rb
  app/api/application_api.rb
  app/models/task.rb
  app/models/board.rb
  app/models/user.rb
  app/cells/task_cell.rb
  app/lib/notify.rb
  app/lib/mailer.rb
  app/jobs/digest_job.rb
]

USERS ||= [
  'alice@example.com', 'bob@example.com', 'carol@example.com',
  'dan@example.com', 'eve@example.com', 'frank@example.com',
  nil, nil
]

URLS ||= [
  'GET /tasks', 'GET /boards', 'POST /api/task.update',
  'GET /admin/plugins/exception_logger', 'POST /api/board.create',
  'GET /notes', 'GET /admin', 'POST /login',
  'PATCH /api/user.update', 'DELETE /api/task.destroy'
]

app_root = Lux.root.to_s

# build backtrace lines that mix app frames (so the formatter highlights them)
# with a couple of gem frames
make_backtrace = lambda do |seed|
  rng = Random.new(seed)
  lines = 8.times.map do
    file   = FILES[rng.rand(FILES.length)]
    line   = rng.rand(20..500)
    method = METHOD_NAMES[rng.rand(METHOD_NAMES.length)]
    klass  = CLASS_NAMES[rng.rand(CLASS_NAMES.length)]
    "#{app_root}/#{file}:#{line}:in `#{klass}##{method}'"
  end
  lines << "/gems/sequel-5.80/lib/sequel.rb:142:in `block in run'"
  lines << "/gems/rack-3.0.0/lib/rack/handler.rb:55:in `call'"
  lines
end

make_message = lambda do |template, rng|
  template.scan(/%[sd]/).inject(template.dup) do |acc, tok|
    val = tok == '%d' ? rng.rand(0..5) :
      %w[id name foo bar baz_key Board ENOENT api.example.com Hash users idx Integer].sample(random: rng)
    acc.sub(tok, val.to_s)
  end
end

exep_created = 0
log_created  = 0
now          = Time.now

100.times do |i|
  rng   = Random.new(i * 7919 + 31)
  klass = ERR_CLASSES.sample(random: rng)
  tmpl  = MSG_TEMPLATES.sample(random: rng)
  msg   = make_message.call(tmpl, rng)
  bt    = make_backtrace.call(i)

  clean_msg = msg.gsub(/:0x\w+/, '')
  app_lines = bt.reject { |el| el.include?('/gems/') || el.include?('/.') }.select { |el| el.include?('.rb') }
  uid       = Digest::SHA1.hexdigest(app_lines[0, 10].join('') + clean_msg + klass)[0, 30]

  # collision guard - rotate uid if already present
  if LuxException.first(uid: uid)
    uid = Digest::SHA1.hexdigest(uid + i.to_s)[0, 30]
  end

  first_at    = now - rng.rand(60..(30 * 24 * 60 * 60))
  last_at     = first_at + rng.rand(0..((now - first_at).to_i))
  times       = [1, 1, 1, 2, 3, 5, 8, 13, 25, 60].sample(random: rng)
  is_resolved = [false, false, false, false, true].sample(random: rng)

  LuxException.create \
    uid: uid,
    klass: klass,
    message: msg,
    body: bt.join("\n"),
    times: times,
    is_resolved: is_resolved,
    first_at: first_at,
    last_at: last_at
  exep_created += 1

  log_count = [times, 5].min
  log_count.times do
    log_at = first_at + rng.rand(0..((last_at - first_at).to_i))
    LuxExceptionLog.create \
      uid: uid,
      created_at: log_at,
      url: URLS.sample(random: rng),
      email: USERS.sample(random: rng),
      ip: '%d.%d.%d.%d' % [rng.rand(1..223), rng.rand(0..255), rng.rand(0..255), rng.rand(1..254)],
      env: { 'REQUEST_METHOD' => %w[GET POST PATCH DELETE].sample(random: rng),
             'HTTP_USER_AGENT' => 'Mozilla/5.0 (seed)',
             'REMOTE_ADDR' => '127.0.0.1',
             'rack.url_scheme' => 'http' }.to_json
    log_created += 1
  end
end

puts "inserted #{exep_created} LuxException rows, #{log_created} LuxExceptionLog rows"
puts "totals - exceptions: #{LuxException.count}, logs: #{LuxExceptionLog.count}"
