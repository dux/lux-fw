class Lux::Type::CurrencyCodeType < Lux::Type
  CURRENCIES ||= %w[
    AED AFN ALL AMD ANG AOA ARS AUD AWG AZN BAM BBD BDT BGN BHD BIF BMD BND
    BOB BRL BSD BTN BWP BYN BZD CAD CDF CHF CLP CNY COP CRC CUP CVE CZK DJF
    DKK DOP DZD EGP ERN ETB EUR FJD FKP GBP GEL GHS GIP GMD GNF GTQ GYD HKD
    HNL HTG HUF IDR ILS INR IQD IRR ISK JMD JOD JPY KES KGS KHR KMF KPW KRW
    KWD KYD KZT LAK LBP LKR LRD LSL LYD MAD MDL MGA MKD MMK MNT MOP MRU MUR
    MVR MWK MXN MYR MZN NAD NGN NIO NOK NPR NZD OMR PAB PEN PGK PHP PKR PLN
    PYG QAR RON RSD RUB RWF SAR SBD SCR SDG SEK SGD SHP SLE SOS SRD SSP STN
    SVC SYP SZL THB TJS TMT TND TOP TRY TTD TWD TZS UAH UGX USD UYU UZS VED
    VES VND VUV WST XAF XCD XOF XPF YER ZAR ZMW ZWL
  ].freeze

  def coerce
    @value = @value.to_s.upcase.strip
    validate
  end

  def db_schema
    [:string, { limit: 3 }]
  end

  private

  def validate
    raise TypeError.new('Currency code must be exactly 3 characters') unless @value.length == 3
    raise TypeError.new(error_for(:unallowed_characters_error)) unless @value =~ /^[A-Z]{3}$/
    raise TypeError.new('Currency code "%s" is not valid' % @value) unless CURRENCIES.include?(@value)
  end
end
