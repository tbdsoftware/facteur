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
  let(:hook_jobs) { Facteur::MailProviderHookJob.jobs }

  before do
    Sidekiq::Job.clear_all
    Facteur.sendgrid_webhook_public_key = SendgridHelpers::PUBLIC_KEY
  end

  it 'enqueues the signed events with string arguments and updates the mailing' do
    post_sendgrid(events.to_json)

    expect(response).to have_http_status(:ok)
    expect(hook_jobs.map { |job| job['args'] }).to eq([['sendgrid', events]])

    Facteur::MailProviderHookJob.drain

    mailing.reload
    expect(mailing.processed_at).to eq(Time.zone.at(1_794_193_288))
    expect(mailing.delivered_at).to eq(Time.zone.at(1_794_193_290))
    expect(mailing.opened_at).to eq(Time.zone.at(1_794_193_300))
    expect(mailing.error_msg).to eq('bounce: 500 unknown recipient')
    expect(mailing).to be_current_status_error
    expect(mailing.events.map { |event| event['sg_event_id'] }).to eq(%w[sg-processed-1 sg-delivered-1 sg-open-1 sg-bounce-1])
  end

  describe 'signature' do
    it 'answers 403 to events whose signature does not match' do
      post_sendgrid(events.to_json, signature: sendgrid_signature('[]', Time.current.to_i.to_s))

      expect(response).to have_http_status(:forbidden)
      expect(hook_jobs).to be_empty
    end

    it 'answers 403 to events signed by another key' do
      other_key = OpenSSL::PKey::EC.generate('prime256v1')
      timestamp = Time.current.to_i.to_s

      post_sendgrid(events.to_json, timestamp: timestamp,
                                    signature: sendgrid_signature(events.to_json, timestamp, key: other_key))

      expect(response).to have_http_status(:forbidden)
      expect(hook_jobs).to be_empty
    end

    it 'answers 403 without signature' do
      post_sendgrid(events.to_json, signature: nil)

      expect(response).to have_http_status(:forbidden)
      expect(hook_jobs).to be_empty
    end

    it 'answers 403 without timestamp' do
      post_sendgrid(events.to_json, timestamp: nil, signature: sendgrid_signature(events.to_json, ''))

      expect(response).to have_http_status(:forbidden)
      expect(hook_jobs).to be_empty
    end

    it 'answers 403 and logs an error when no public key is configured' do
      Facteur.sendgrid_webhook_public_key = nil
      allow(Rails.logger).to receive(:error)

      post_sendgrid(events.to_json)

      expect(response).to have_http_status(:forbidden)
      expect(hook_jobs).to be_empty
      expect(Rails.logger).to have_received(:error).with(/sendgrid_webhook_public_key is not configured/)
    end

    it 'answers 403 when the configured public key is malformed' do
      Facteur.sendgrid_webhook_public_key = 'not a key'

      post_sendgrid(events.to_json)

      expect(response).to have_http_status(:forbidden)
      expect(hook_jobs).to be_empty
    end
  end

  describe 'payload' do
    it 'answers 413 to a body over 1 MB' do
      post_sendgrid([{ 'event' => 'processed', 'padding' => 'a' * Facteur::WebhooksController::MAX_BODY_BYTES }].to_json)

      expect(response).to have_http_status(413)
      expect(hook_jobs).to be_empty
    end

    it 'answers 413 to more than 5 000 events' do
      post_sendgrid(Array.new(Facteur::WebhooksController::MAX_EVENTS + 1) { { 'event' => 'processed' } }.to_json)

      expect(response).to have_http_status(413)
      expect(hook_jobs).to be_empty
    end

    it 'accepts 5 000 events' do
      post_sendgrid(Array.new(Facteur::WebhooksController::MAX_EVENTS) { { 'event' => 'processed' } }.to_json)

      expect(response).to have_http_status(:ok)
      expect(hook_jobs.size).to eq(1)
    end

    ['{"event":"processed"}', '[1, 2]', '["processed"]', 'not json', ''].each do |body|
      it "answers 400 to #{body.inspect}, which is not a JSON array of objects" do
        post_sendgrid(body)

        expect(response).to have_http_status(:bad_request)
        expect(hook_jobs).to be_empty
      end
    end
  end
end
