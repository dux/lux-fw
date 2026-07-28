# Lux::Utils::Ref - the short name for the app's declared ref format.
#
# The format is named by Lux.config.ref_format and resolved through
# Lux::Application::Nav::Base, so the router, the db column type and model
# primary keys all agree on what an id is. This is the facade models and
# plugins call.
#
#   Lux::Utils::Ref.generate      # -> "k3p9x2mq7wd1nb84", or a uuid7, ...
#   Lux::Utils::Ref.is?(segment)  # -> true / false
#
# The db plugin reopens this module to add the model registry (register / klass
# / load / models / public_link), which needs Sequel and stays out of core.

module Lux
module Utils
module Ref
  extend self

  # An instance of the declared format. Resolved per call, not memoized, so a
  # host that sets ref_format after this file loads still gets its own format.
  def format value = nil
    Lux::Application::Nav::Base.build value
  end

  # Extra args go to the format's #generate - RefString takes a length.
  def generate *args
    format.generate(*args).value
  end

  def is? text
    format(text).valid?
  end
end
end
end
