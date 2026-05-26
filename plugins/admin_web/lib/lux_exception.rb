# Deduplicated exception record. One row per unique (backtrace + message + class)
# fingerprint. Per-occurrence detail is stored in LuxExceptionLog.

class LuxException < ApplicationModel
  schema do
    uid String, max: 30, index: true
    klass String, index: true
    message? :text
    body? :text
    times Integer, default: 1
    is_resolved? :boolean
    first_at Time
    last_at Time, index: true
  end

  IGNORE ||= ['Lux::Error', 'Lux::Api::Error']

  class << self
    # Compact "Ns/m/h/d ago" - used by the admin views without pulling in
    # an extra helper module.
    def time_ago time
      return '' unless time
      diff = Time.now - time
      case diff
      when 0..59 then "#{diff.to_i}s ago"
      when 60..3599 then "#{(diff / 60).to_i}m ago"
      when 3600..86399 then "#{(diff / 3600).to_i}h ago"
      else "#{(diff / 86400).to_i}d ago"
      end
    end

    def trim str, n
      s = str.to_s
      s.length > n ? s[0, n] + '...' : s
    end

    def fingerprint error
      lines = (error.backtrace || [])
        .reject { |el| el.include?('/gems/') || el.include?('/.') }
        .select { |el| el.include?('.rb') }

      clean_msg = error.message.gsub(/:0x\w+/, '')

      Digest::SHA1.hexdigest(lines[0, 10].join('') + clean_msg + error.class.to_s)[0, 30]
    end

    def add error
      uid = fingerprint error

      if exep = LuxException.first(uid: uid)
        exep.update times: exep.times + 1, last_at: Time.now
      else
        exep = LuxException.create \
          uid: uid,
          klass: error.class.to_s,
          message: error.message,
          body: (error.backtrace.join($/) rescue nil),
          times: 1,
          first_at: Time.now,
          last_at: Time.now
      end

      email = User.current.email rescue nil
      ip    = Lux.current.request.ip rescue nil
      url   = [Lux.current.request.request_method, Lux.current.request.url[0, 200]].join(' ') rescue nil
      env   = (Lux.current.request.env.reject { |k, v| ![String, TrueClass, FalseClass, Integer].include?(v.class) || k.downcase.include?('cookie') }.to_json rescue nil)

      LuxExceptionLog.create uid: uid, url: url, email: email, ip: ip, env: env

      exep
    end

    def get_list params = {}
      params = params.dup
      params.delete(:klass) unless params[:klass]
      email = params.delete :email

      list = LuxException.order(Sequel.desc(:last_at))

      unless params[:klass]
        list = list.exclude(klass: IGNORE)
      end

      list = list.where(params) if params.any?

      if email
        log_uids = LuxExceptionLog
          .where { created_at > 12.month.ago }
          .where(email: email)
          .select(:uid)
        list = list.where(uid: log_uids)
      end

      list.limit(200).all
    end

    def get_users
      LuxExceptionLog
        .where { created_at > 7.days.ago }
        .exclude(email: nil)
        .group_and_count(:email)
        .order(Sequel.desc(:count))
        .limit(7)
        .all
    end

    def get_error_types
      LuxException
        .where { last_at > 3.month.ago }
        .group_and_count(:klass)
        .order(Sequel.desc(:count))
        .limit(100)
        .all
    end

    def quick_summary
      {
        day: quick_summary_for(1.days.ago),
        week: quick_summary_for(7.days.ago),
        month: quick_summary_for(1.month.ago)
      }
    end

    def get_exp uid
      exep = LuxException.first(uid: uid) or return nil
      logs = LuxExceptionLog.where(uid: uid).order(Sequel.desc(:created_at)).limit(200).all
      body = ("\n" + exep.body.to_s).gsub(Lux.root.to_s, '.').gsub(/\n\.([^\n]+)$/, "\n<b>.\\1</b>")
      {
        ref: exep.ref,
        uid: exep.uid,
        klass: exep.klass,
        message: exep.message,
        body: body,
        times: exep.times,
        is_resolved: exep.is_resolved,
        first_at: exep.first_at,
        last_at: exep.last_at,
        logs: logs.map(&:values)
      }
    end

    def size
      LuxException.count
    end

    private

    def quick_summary_for since
      base = LuxException.exclude(klass: IGNORE)

      {
        new: base.where { first_at > since }.count,
        unresolved: base.where { last_at > since }.where(Sequel.|({ is_resolved: nil }, { is_resolved: false })).count,
        resolved: base.where { last_at > since }.where(is_resolved: true).count
      }
    end
  end
end
