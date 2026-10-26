require 'test_helper'
require 'mail'   # the app's Gemfile provides the gem; lux does not require it

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

  describe '.parse Authentication-Results' do
    def raw_mail
      <<~MAIL.gsub("\n", "\r\n")
        Authentication-Results: evil.example; dmarc=pass
        Authentication-Results: mx.trusted.example 1; spf=pass; dmarc=fail
        From: user@gmail.com
        To: a@b.com
        Subject: hi

        body
      MAIL
    end

    def with_trusted ids
      mail = Lux.config[:mail]
      Lux.config[:mail] = (mail || {}).to_h.merge(trusted_authserv_ids: ids)
      yield
    ensure
      Lux.config[:mail] = mail
    end

    it 'reads verdicts only from a trusted authserv-id' do
      with_trusted(['mx.trusted.example']) do
        msg = Lux::Mail::Inbox.parse(raw_mail)
        _(msg.dmarc).must_equal    'fail'
        _(msg.spf).must_equal      'pass'
        _(msg.verified).must_equal false
      end
    end

    it 'is never verified without configured authserv-ids' do
      with_trusted(nil) do
        msg = Lux::Mail::Inbox.parse(raw_mail)
        _(msg.dmarc).must_be_nil
        _(msg.verified).must_equal false
      end
    end
  end
end
