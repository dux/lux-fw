require 'test_helper'

###

VcUser ||= Struct.new :name, :email

class AppCell < Lux::ViewCell
  before do
    @numbers = [123]
  end

  css %[
    .foo {
      .bar {
        font-weight: bold;
      }
    }
  ]
end

class VcUserCell < AppCell
  delegate :email

  template_root './spec/view_cell_tests/misc'

  css 'css/user.scss'

  def before
    super
    @numbers.push 456
  end

  def sq num
    num * num
  end

  def numbers
    @numbers.join '-'
  end

  def profile
    @user = parent { @user }
    template :profile
  end

  def profiles
    @users = [VcUser.new('dux', 'dux@net'), VcUser.new('foo', 'foo@net')]
    template 'profiles'
  end

  def not_found
    template :not_found
  end

  def uemail
    email
  end

  def render user
    '>%s<' % user.name
  end
end

###

describe 'Lux::ViewCell common' do
  def user
    @user_obj ||= VcUser.new 'Dux', 'dux@net.net'
  end

  it 'can call plain function' do
    num = VcUserCell.new.sq 4
    _(num).must_equal 16
  end

  it 'resoves before filters well' do
    num = VcUserCell.new.numbers
    _(num).must_equal '123-456'
  end

  it 'raises render error' do
    _{ VcUserCell.new.not_found }.must_raise ArgumentError
  end

  it 'renders template with parent instance variables' do
    @user = user
    data  = VcUserCell.new(self).profile
    _(data).must_equal 'foo Dux bar'
  end

  it 'renders template with variable lists' do
    data  = VcUserCell.new.profiles
    _(data).must_equal 'x >dux<>foo< x >dux< x'
  end

  it 'can deleate functions to parent scope' do
    # user object is parent scope!
    data = VcUserCell.new(user).uemail
    _(data).must_equal 'dux@net.net'
  end
end
