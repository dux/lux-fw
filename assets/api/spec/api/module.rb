module ApiModuleClasic
  def self.included base
    base.class_eval do
      define :module_clasic do
        proc { 'is_module' }
      end
    end
  end
end

Lux::Api.plugin :test_1 do
  define :plugin_test do
    proc { 'from_plugin' }
  end
end
