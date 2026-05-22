class User < Struct.new(:name, :email, :is_admin)
  def company
    Company.new('ACME corp', 'Nowhere 123')
  end
end

class Company < Struct.new(:name, :address)
  def name
    'ACME corp'
  end

  def creator
    User.new('miki', 'miki@riki.net', true)
  end
end

class ApplicationApi
  model User do
    name
    email     :email
    is_admin? :boolean
  end

  model Company do
    name
    address?
    oib?      :oib
  end
end
