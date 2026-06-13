require 'test_helper'

describe Lux::Mail::Inbox do
  def payload
    {
      to:      'sohotasks@support.authcog.com',
      from:    'user@gmail.com',
      subject: 'Need help',
      text:    'hello',
      dmarc:   'pass',
    }
  end

  describe 'Message' do
    it 'normalizes recipient parts and the dmarc verdict' do
      msg = Lux::Mail::Inbox.receive(payload, :post)
      _(msg.local).must_equal    'sohotasks'
      _(msg.domain).must_equal   'support.authcog.com'
      _(msg.verified).must_equal true
      _(msg.source).must_equal   :post
    end

    it 'marks a dmarc failure as unverified' do
      msg = Lux::Mail::Inbox.receive(payload.merge(dmarc: 'fail'), :mailbox)
      _(msg.verified).must_equal false
      _(msg.source).must_equal   :mailbox
    end
  end

  describe '.receive' do
    it 'fans out to on_receive handlers with (mail, type)' do
      got = []
      Lux::Mail::Inbox.on_receive { |mail, type| got << [mail.local, type] }
      Lux.mail_received(payload, :post)
      _(got).must_include ['sohotasks', :post]
    end

    it 'passes a Message through unchanged but stamps the source' do
      msg = Lux::Mail::Inbox::Message.new(to: 'a@b.com', dmarc: 'pass')
      out = Lux::Mail::Inbox.receive(msg, :mailbox)
      assert out.equal?(msg)
      _(out.source).must_equal :mailbox
    end
  end
end
