class Module
  # creates instance with module included and runs the code
  # MainHelper.runtime_eval do
  #   @session_city = City.first
  #   header_top_menu
  # end
  def runtime_eval &block
    Class.new.send(:include, self).new.instance_exec &block
  end
end
