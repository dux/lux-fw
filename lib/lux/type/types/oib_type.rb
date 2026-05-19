class Lux::Type::OibType < Lux::Type
  error :en, :not_an_oib_error, 'not in an OIB format'

  def coerce
    value do |data|
      check?(data) ? data.to_s : error_for(:not_an_oib_error)
    end
  end

  def db_schema
    [:string, {
      limit: 11
    }]
  end

  private

  # http://domagoj.eu/oib/
  def check? oib
    oib = oib.to_s

    return false unless oib.match(/^[0-9]{11}$/)

    control_sum = (0..9).inject(10) do |middle, position|
      middle += oib[position].to_i
      middle %= 10
      middle = 10 if middle == 0
      middle *= 2
      middle %= 11
    end

    control_sum = 11 - control_sum
    control_sum = 0 if control_sum == 10

    return control_sum == oib[10].to_i
  end
end
