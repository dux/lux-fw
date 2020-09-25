module Sequel::Plugins::LuxTouch
  module InstanceMethods
    def touch with_callbacks=false
      # only touch objects once per session
      Lux.current.once 'lux-touch-%s-%s' % [self.class, id] do
        if with_callbacks
          update updated_at: Time.now.utc
        else
          if id
            DB.run 'update %s set updated_at=now() where id=%s' % [self.class.table_name, id]
          end

          touch_on = db_schema.select { |k,v| k.to_s.end_with?('_id') && v[:db_type] == 'integer' }.keys

          for field in touch_on
            if klass = field.to_s.sub(/_id$/, '').classify.constantize?
              target_id = self[field]
              desc      = "#{self.class}[#{id}].#{field} -> #{klass}[#{target_id}].touch"

              Lux.current.once 'lux-touch-inner-%s-%s' % [klass, target_id] do
                if object = klass[target_id]
                  Lux.log ' Cache clear: %s' % desc
                  object.touch
                else
                  Lux.log "Possible linked object #{desc} not found, skipping cache clear".red
                end
              end
            end
          end
        end
      end

      self
    end

    def after_change
      touch
      super
    end
  end
end

Sequel::Model.plugin :lux_touch