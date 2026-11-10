# frozen_string_literal: true

# Replica of the manual test of 09/11: real TEM payloads replayed against a mailing delivered by Facteur
RSpec.describe 'Scaleway TEM end to end' do
  let(:token) { 'scaleway-secret-token' }
  let(:mailbox_not_found_reason) do
    JSON.parse(fixture_envelope('05_notification_email_mailbox_not_found.json')['Message'])['email_response_message'].strip
  end

  before do
    Facteur.provider = :scaleway
    Facteur.scaleway_webhook_token = token
    stub_test_certificate
  end

  def deliver_mailing(to)
    mailing = Facteur::Mailing.create!(mailer_klass: 'TestMailer', mailer_method: 'welcome', mailer_params: [to])
    Facteur::MailingDeliveryJob.drain
    mailing.reload
  end

  def replay(mailing, fixtures, times: 1)
    times.times do
      fixtures.each do |fixture|
        post_sns(signed_event_envelope(fixture, mailing.id), token: token)
        expect(response).to have_http_status(:ok)
      end
    end
    Sidekiq::Job.drain_all
    mailing.reload
  end

  def expect_header(mailing)
    mail = ActionMailer::Base.deliveries.last
    expect(mail['X-Facteur-Mailing-Id'].value).to eq(mailing.id.to_s)
    expect(mail['X-SMTPAPI']).to be_nil
    expect(mailing).to be_current_status_sent
  end

  def snapshot(mailing)
    mailing.attributes.slice('status', 'processed_at', 'delivered_at', 'error_at', 'error_msg', 'provider_message_ids')
      .merge('event_ids' => mailing.events.map { |event| event['provider_event_id'] })
  end

  scenarios = {
    'a real address' => {
      fixtures: %w[02_notification_email_queued.json 03_notification_email_delivered.json],
      check: lambda do |mailing|
        expect(mailing).to be_current_status_delivered
        expect(mailing.processed_at).to be_present
        expect(mailing.delivered_at).to be_present
        expect(mailing.error_at).to be_nil
        expect(mailing.provider_message_ids).to eq(['eeecec74-a810-4a8a-b792-0ca83f0d822e'])
      end
    },
    'a non-existent address' => {
      fixtures: %w[04_notification_email_queued.json 07_notification_email_dropped.json
                   05_notification_email_mailbox_not_found.json 06_notification_blocklist_created.json],
      check: lambda do |mailing|
        expect(mailing).to be_current_status_error
        expect(mailing.error_msg).to eq("email_mailbox_not_found: #{mailbox_not_found_reason}")
        expect(mailing.events.map { |event| event['type'] })
          .to eq(%w[email_queued email_dropped email_mailbox_not_found])
      end
    },
    'a domain without MX' => {
      fixtures: %w[08_notification_email_queued.json 09_notification_email_dropped.json],
      check: lambda do |mailing|
        expect(mailing).to be_current_status_error
        expect(mailing.error_msg).to eq('email_dropped: send email to facteur-test-nomx-d3ab0cfd908a.com: ' \
                                        'non-existing domain or no MX found')
      end
    }
  }

  scenarios.each do |name, scenario|
    it "tracks a mail sent to #{name}" do
      mailing = deliver_mailing('jane@facteur.test')
      expect_header(mailing)

      instance_exec(replay(mailing, scenario[:fixtures]), &scenario[:check])
    end

    it "gets the same result for #{name} when every payload is posted twice" do
      once = deliver_mailing('jane@facteur.test')
      twice = deliver_mailing('john@facteur.test')

      replay(once, scenario[:fixtures])
      replay(twice, scenario[:fixtures], times: 2)

      instance_exec(twice, &scenario[:check])
      expect(snapshot(twice)).to eq(snapshot(once))
    end
  end

  it 'tracks a mail to an invalid address refused by SMTP, without retry' do
    error = Net::SMTPSyntaxError.new(Net::SMTP::Response.parse("501 5.1.3 Bad recipient address syntax\n"))
    allow_any_instance_of(Mail::TestMailer).to receive(:deliver!).and_raise(error)

    mailing = Facteur::Mailing.create!(mailer_klass: 'TestMailer', mailer_method: 'welcome',
                                       mailer_params: ['not-an-address@@facteur.test'])
    expect { Facteur::MailingDeliveryJob.drain }.not_to raise_error

    mailing.reload
    expect(mailing).to be_current_status_error
    expect(mailing.error_msg).to eq('smtp_rejected: 501 5.1.3 Bad recipient address syntax')
    expect(mailing.sent_at).to be_nil
    expect(Facteur::MailingDeliveryJob.jobs).to be_empty
  end
end
