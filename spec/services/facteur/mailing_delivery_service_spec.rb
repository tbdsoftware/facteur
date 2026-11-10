# frozen_string_literal: true

RSpec.describe Facteur::MailingDeliveryService do
  def create_mailing(to: 'jane@facteur.test', mailer_klass: 'TestMailer', **attributes)
    Facteur::Mailing.create!(mailer_klass: mailer_klass, mailer_method: 'welcome', mailer_params: [to], **attributes)
  end

  def deliver(mailing)
    described_class.new(mailing).call
  end

  let(:mailing) { create_mailing }
  let(:delivered_mail) { ActionMailer::Base.deliveries.last }

  describe 'headers' do
    it 'delivers the mail with the X-Facteur-Mailing-Id header' do
      deliver(mailing)

      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(delivered_mail['X-Facteur-Mailing-Id'].value).to eq(mailing.id.to_s)
      expect(mailing.reload).to be_current_status_sent
      expect(mailing.sent_at).to be_present
    end

    it 'delivers a parameterized mailer' do
      mailing = Facteur::Mailing.create!(mailer_klass: 'TestMailer', mailer_method: 'notification',
                                         mailer_params: { to: 'john@facteur.test', subject: 'Hi' })

      deliver(mailing)

      expect(delivered_mail.to).to eq(['john@facteur.test'])
      expect(delivered_mail['X-Facteur-Mailing-Id'].value).to eq(mailing.id.to_s)
      expect(mailing.reload.subject).to eq('Hi')
    end

    it 'adds X-SMTPAPI when the provider is sendgrid, whatever the environment' do
      Facteur.provider = :sendgrid
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('production'))

      deliver(mailing)

      expect(JSON.parse(delivered_mail['X-SMTPAPI'].value)).to eq('unique_args' => { 'mn_id' => mailing.id })
    end

    it 'does not add X-SMTPAPI when the provider is scaleway, whatever the environment' do
      Facteur.provider = :scaleway
      allow(Rails).to receive(:env).and_return(ActiveSupport::EnvironmentInquirer.new('development'))

      deliver(mailing)

      expect(delivered_mail['X-SMTPAPI']).to be_nil
      expect(delivered_mail['X-Facteur-Mailing-Id'].value).to eq(mailing.id.to_s)
    end
  end

  describe 'permanent SMTP refusal' do
    [
      Net::SMTPSyntaxError.new(Net::SMTP::Response.parse("501 5.1.3 Bad recipient address syntax\n")),
      Net::SMTPFatalError.new(Net::SMTP::Response.parse("554 5.7.1 Relay access denied\n"))
    ].each do |error|
      it "records #{error.class} as an error without raising" do
        allow_any_instance_of(Mail::TestMailer).to receive(:deliver!).and_raise(error)

        expect { deliver(mailing) }.not_to raise_error

        mailing.reload
        expect(mailing).to be_current_status_error
        expect(mailing.error_msg).to eq("smtp_rejected: #{error.message.strip}")
        expect(mailing.error_at).to be_present
        expect(mailing.sent_at).to be_nil
        expect(mailing.events.last).to include('event' => 'dropped', 'type' => 'smtp_rejected', 'provider' => 'smtp',
                                               'provider_event_id' => nil)
      end
    end

    it 'does not try again when the job runs again' do
      error = Net::SMTPSyntaxError.new(Net::SMTP::Response.parse("501 5.1.3 Bad recipient address syntax\n"))
      attempts = 0
      allow_any_instance_of(Mail::TestMailer).to receive(:deliver!) do
        attempts += 1
        raise error
      end
      deliver(mailing)

      Facteur::MailingDeliveryJob.new.perform(mailing.id)

      expect(attempts).to eq(1)
      expect(mailing.reload.events.size).to eq(1)
      expect(ActionMailer::Base.deliveries).to be_empty
    end
  end

  describe 'temporary failures' do
    [
      Net::SMTPServerBusy.new(Net::SMTP::Response.parse("451 4.3.0 Try again later\n")),
      Net::ReadTimeout.new
    ].each do |error|
      it "lets #{error.class} propagate so Sidekiq retries" do
        allow_any_instance_of(Mail::TestMailer).to receive(:deliver!).and_raise(error)

        expect { deliver(mailing) }.to raise_error(error.class)

        mailing.reload
        expect(mailing).to be_current_status_pending
        expect(mailing.sent_at).to be_nil
        expect(mailing.error_at).to be_nil
      end
    end
  end

  describe 'never-sent mailings' do
    it 'skips an expired mailing without building nor sending the mail' do
      mailing = create_mailing(created_at: 2.days.ago)
      expect(TestMailer).not_to receive(:welcome)

      deliver(mailing)

      mailing.reload
      expect(mailing).to be_current_status_skipped
      expect(mailing.skip_reason).to eq('expired')
      expect(mailing.skipped_at).to be_present
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'skips a mailing when the mailer asks to' do
      mailing = create_mailing(mailer_klass: 'SkippingMailer')

      deliver(mailing)

      expect(mailing.reload).to be_current_status_skipped
      expect(mailing.skip_reason).to eq('skipped')
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'skips a mailing to an @example.com recipient' do
      mailing = create_mailing(to: 'jane@example.com')

      deliver(mailing)

      expect(mailing.reload).to be_current_status_skipped
      expect(mailing.skip_reason).to eq('blocked_recipient')
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'skips a mailing without recipient' do
      mailing = create_mailing(to: nil)

      deliver(mailing)

      expect(mailing.reload).to be_current_status_skipped
      expect(mailing.skip_reason).to eq('blocked_recipient')
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it 'does not send a skipped mailing when the job runs again' do
      mailing = create_mailing(to: 'jane@example.com')
      deliver(mailing)
      skipped_at = mailing.reload.skipped_at

      Facteur::MailingDeliveryJob.new.perform(mailing.id)

      expect(ActionMailer::Base.deliveries).to be_empty
      expect(mailing.reload.skipped_at).to eq(skipped_at)
    end

    it 'does not send a sent mailing twice' do
      deliver(mailing)
      Facteur::MailingDeliveryJob.new.perform(mailing.id)

      expect(ActionMailer::Base.deliveries.size).to eq(1)
    end

    it 'rejects unknown skip reasons' do
      mailing.skip_reason = 'whatever'

      expect(mailing).not_to be_valid
    end
  end
end
