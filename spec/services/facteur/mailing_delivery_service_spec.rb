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

  describe 'tokens' do
    def create_reset_mailing(token: 'raw-reset-token', to: 'jane@facteur.test', **attributes)
      Facteur::Mailing.create!(mailer_klass: 'TestMailer', mailer_method: 'reset_password_instructions',
                               mailer_params: [token, { 'to' => to }], **attributes)
    end

    it 'sends the raw token but stores the body filtered' do
      mailing = create_reset_mailing

      deliver(mailing)

      expect(delivered_mail.body.decoded).to include('reset_password_token=raw-reset-token')
      expect(mailing.reload.body).to include('reset_password_token=[FILTERED]&amp;locale=fr')
      expect(mailing.body).not_to include('raw-reset-token')
    end

    it 'filters the token out of the mailer_params of a sent mailing' do
      mailing = create_reset_mailing

      deliver(mailing)

      expect(mailing.reload).to be_current_status_sent
      expect(mailing.mailer_params).to eq(['[FILTERED]', { 'to' => 'jane@facteur.test' }])
    end

    it 'filters the token out of the mailer_params of a skipped mailing' do
      blocked = create_reset_mailing(to: 'jane@example.com')
      expired = create_reset_mailing(created_at: 2.days.ago)

      [blocked, expired].each { |mailing| deliver(mailing) }

      expect(blocked.reload.skip_reason).to eq('blocked_recipient')
      expect(expired.reload.skip_reason).to eq('expired')
      expect(blocked.mailer_params).to eq(['[FILTERED]', { 'to' => 'jane@example.com' }])
      expect(expired.mailer_params).to eq(['[FILTERED]', { 'to' => 'jane@facteur.test' }])
      expect(blocked.body).not_to include('raw-reset-token')
    end

    it 'filters the token out of the mailer_params of a mailing refused by SMTP' do
      error = Net::SMTPFatalError.new(Net::SMTP::Response.parse("554 5.7.1 Relay access denied\n"))
      allow_any_instance_of(Mail::TestMailer).to receive(:deliver!).and_raise(error)
      mailing = create_reset_mailing

      deliver(mailing)

      expect(mailing.reload).to be_current_status_error
      expect(mailing.mailer_params.first).to eq('[FILTERED]')
    end

    it 'keeps the raw token for the retry when the delivery raised, but never stores it in the body' do
      allow_any_instance_of(Mail::TestMailer).to receive(:deliver!).and_raise(Net::ReadTimeout)
      mailing = create_reset_mailing

      expect { deliver(mailing) }.to raise_error(Net::ReadTimeout)

      mailing.reload
      expect(mailing).to be_current_status_pending
      expect(mailing.mailer_params).to eq(['raw-reset-token', { 'to' => 'jane@facteur.test' }])
      expect(mailing.body).to include('reset_password_token=[FILTERED]')
    end

    it 'sends the raw token again on retry' do
      attempts = 0
      allow_any_instance_of(Mail::TestMailer).to receive(:deliver!).and_wrap_original do |original, *args|
        attempts += 1
        raise Net::ReadTimeout if attempts == 1

        original.call(*args)
      end
      mailing = create_reset_mailing
      expect { deliver(mailing) }.to raise_error(Net::ReadTimeout)

      Facteur::MailingDeliveryJob.new.perform(mailing.id)

      expect(delivered_mail.body.decoded).to include('reset_password_token=raw-reset-token')
      expect(mailing.reload.mailer_params.first).to eq('[FILTERED]')
    end
  end

  describe 'store_body' do
    it 'stores the body by default' do
      deliver(mailing)

      expect(mailing.reload.body).to eq('Hello jane@facteur.test')
    end

    it 'stores no body when disabled' do
      Facteur.store_body = false

      deliver(mailing)

      expect(ActionMailer::Base.deliveries.size).to eq(1)
      expect(mailing.reload.body).to be_nil
      expect(mailing.subject).to eq('Welcome')
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
