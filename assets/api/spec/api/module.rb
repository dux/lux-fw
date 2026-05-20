module ApiModuleClasic
  def self.included base
    base.class_eval do
      def module_clasic
        'is_module'
      end
    end
  end
end

Lux::Api.plugin :test_1 do
  def plugin_test
    'from_plugin'
  end
end
