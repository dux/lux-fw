namespace :mail do
  task :pull do
    desc 'Pull unseen mail from configured IMAP inbox(es); fires Lux.mail_received(mail, :mailbox) per message'
    needs :app   # app boot loads config[:mail] and the on_receive handler

    proc do |_opts|
      Lux::Mail::Inbox.pull
    end
  end
end
