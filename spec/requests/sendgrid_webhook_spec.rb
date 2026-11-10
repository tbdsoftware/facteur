# frozen_string_literal: true

RSpec.describe 'POST /facteur/sendgrid' do
  let(:mailing) do
    Facteur::Mailing.create!(mailer_klass: 'TestMailer', mailer_method: 'welcome', mailer_params: ['jane@facteur.test'],
                             to: 'jane@facteur.test', sent_at: Time.current)
  end
  let(:events) do
    [
      { 'email' => 'jane@facteur.test', 'timestamp' => 1_794_193_288, 'event' => 'processed', 'mn_id' => mailing.id.to_s,
        'sg_event_id' => 'sg-processed-1', 'sg_message_id' => 'sg-message-1' },
      { 'email' => 'jane@facteur.test', 'timestamp' => 1_794_193_290, 'event' => 'delivered', 'mn_id' => mailing.id.to_s,
        'sg_event_id' => 'sg-delivered-1', 'sg_message_id' => 'sg-message-1' },
      { 'email' => 'jane@facteur.test', 'timestamp' => 1_794_193_300, 'event' => 'open', 'mn_id' => mailing.id.to_s,
        'sg_event_id' => 'sg-open-1', 'sg_message_id' => 'sg-message-1' },
      { 'email' => 'jane@facteur.test', 'timestamp' => 1_794_193_310, 'event' => 'bounce', 'mn_id' => mailing.id.to_s,
        'type' => 'bounce', 'reason' => '500 unknown recipient', 'status' => '5.0.0',
        'sg_event_id' => 'sg-bounce-1', 'sg_message_id' => 'sg-message-1' }
    ]
  end

  before { Sidekiq::Job.clear_all }

  it 'enqueues the events with string arguments and updates the mailing' do
    post '/facteur/sendgrid', params: events.to_json, headers: { 'Content-Type' => 'application/json' }

    expect(response).to have_http_status(:ok)
    expect(Facteur::MailProviderHookJob.jobs.map { |job| job['args'] }).to eq([['sendgrid', events]])

    Facteur::MailProviderHookJob.drain

    mailing.reload
    expect(mailing.processed_at).to eq(Time.zone.at(1_794_193_288))
    expect(mailing.delivered_at).to eq(Time.zone.at(1_794_193_290))
    expect(mailing.opened_at).to eq(Time.zone.at(1_794_193_300))
    expect(mailing.error_msg).to eq('bounce: 500 unknown recipient')
    expect(mailing).to be_current_status_error
    expect(mailing.events.map { |event| event['sg_event_id'] }).to eq(%w[sg-processed-1 sg-delivered-1 sg-open-1 sg-bounce-1])
  end

  it 'accepts an empty body' do
    post '/facteur/sendgrid'

    expect(response).to have_http_status(:ok)
    expect(Facteur::MailProviderHookJob.jobs.map { |job| job['args'] }).to eq([['sendgrid', nil]])
  end
end
