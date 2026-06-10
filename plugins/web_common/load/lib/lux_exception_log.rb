# Per-occurrence record for an exception fingerprint stored in LuxException.
# Joined via :uid (LuxException#uid -> LuxExceptionLog#uid).

class LuxExceptionLog < ApplicationModel
  schema do
    uid String, max: 30, index: true
    url? :text
    email? String, index: true
    ip? String
    env? :text
    created_at? Time, index: true
  end
end
