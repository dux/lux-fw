require 'test_helper'
require 'mail'   # the app's Gemfile provides the gem; lux does not require it

# delivery stubbed: every built message uses the mail gem's :test method
class SpecSenderMailer < Lux::Mail::Sender
  on_deliver do |m|
    m.delivery_method :test
  end

  def welcome email, name: 'there'
    mail.from    = 'app@example.com'
    mail.to      = email
    mail.cc      = 'boss@example.com'
    mail.subject = "Hi #{name}"
    mail.body    = %[<a href="/x">x</a> <a href="//cdn.example.com/a">cdn</a>]
  end

  def notify opts, email
    mail.from    = 'app@example.com'
    mail.to      = email
    mail.subject = "kind #{opts[:kind]}"
    mail.body    = 'n'
  end

  def cancelled
    mail.to = false
  end

  # Kernel#test is private on every object, so a mail named test shadows it
  def test
    mail.to      = 't@example.com'
    mail.subject = 'test mail'
  end
end

describe Lux::Mail::Sender do
  it 'delivers through the class-level deliver(:name, arg)' do
    m = SpecSenderMailer.deliver(:welcome, 'a@example.com')
    assert_kind_of ::Mail::Message, m
    assert_equal ['a@example.com'], m.to
    assert_equal 'Hi there', m.subject
  end

  it 'passes keyword arguments through' do
    m = SpecSenderMailer.deliver(:welcome, 'a@example.com', name: 'Dux')
    assert_equal 'Hi Dux', m.subject
  end

  it 'keeps the other arguments when the first one is a hash' do
    m = SpecSenderMailer.deliver(:notify, { kind: 1 }, 'b@example.com')
    assert_equal ['b@example.com'], m.to
    assert_equal 'kind 1', m.subject
  end

  it 'sends cc' do
    m = SpecSenderMailer.deliver(:welcome, 'a@example.com')
    assert_equal ['boss@example.com'], m.cc
  end

  it 'leaves protocol-relative links alone' do
    body = SpecSenderMailer.render(:welcome, 'a@example.com')
    assert_includes body, %[href="//cdn.example.com/a"]
    refute_includes body, %[href="/x"]
  end

  it 'returns nil when delivery is cancelled' do
    assert_nil SpecSenderMailer.deliver(:cancelled)
  end

  it 'supports method_missing style for defined mails only' do
    assert_equal 'Hi there', SpecSenderMailer.welcome('a@example.com').subject
    assert_raises(NoMethodError) { SpecSenderMailer.system('true') }
    refute SpecSenderMailer.respond_to?(:build_mail_object)
  end

  it 'reaches a mail that reuses a Kernel method name' do
    assert_equal 'test mail', SpecSenderMailer.test.subject
    assert SpecSenderMailer.respond_to?(:test)
  end
end
