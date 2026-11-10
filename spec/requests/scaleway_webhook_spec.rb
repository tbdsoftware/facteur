# frozen_string_literal: true

RSpec.describe 'POST /facteur/scaleway' do
  let(:token) { 'scaleway-secret-token' }
  let(:hook_jobs) { Facteur::MailProviderHookJob.jobs }
  let(:foreign_topic_arn) { 'arn:scw:sns:fr-par:project-00000000-0000-0000-0000-000000000000:someone-else' }

  before do
    Facteur.scaleway_webhook_token = token
    Facteur.scaleway_topic_arns = [SnsHelpers::TOPIC_ARN]
    travel_to_fixtures_time
  end

  def capture_log
    io = StringIO.new
    logger = ActiveSupport::Logger.new(io)
    Rails.logger.broadcast_to(logger)
    yield
    io.string
  ensure
    Rails.logger.stop_broadcasting_to(logger)
  end

  context 'with real Scaleway signed payloads' do
    before { stub_real_certificate }

    %w[email_queued email_dropped].each do |type|
      it "accepts signed_raw/#{type}.json posted as text/plain and enqueues its parsed payload" do
        raw = fixture_raw("signed_raw/#{type}.json")

        post_sns(raw, token: token)

        expect(response).to have_http_status(:ok)
        expect(hook_jobs.size).to eq(1)
        expect(hook_jobs.first['args']).to eq(['scaleway', JSON.parse(JSON.parse(raw)['Message'])])
      end
    end

    it 'refuses a payload with one character changed in Message' do
      raw = fixture_raw('signed_raw/email_queued.json').sub('email_queued', 'email_queuee')

      post_sns(raw, token: token)

      expect(response).to have_http_status(:forbidden)
      expect(hook_jobs).to be_empty
    end

    it 'fetches the certificate once for two requests' do
      post_sns(fixture_raw('signed_raw/email_queued.json'), token: token)
      post_sns(fixture_raw('signed_raw/email_dropped.json'), token: token)

      expect(hook_jobs.size).to eq(2)
      expect(a_request(:get, SnsHelpers::REAL_CERT_URL)).to have_been_made.once
    end
  end

  context 'with a SigningCertURL outside Scaleway' do
    %w[https://evil.example.com/x.pem
       http://messaging.s3.fr-par.scw.cloud/fr-par/sns/sns_certificate_0123456789abcdef.pem
       https://messaging.s3.fr-par.scw.cloud:8443/fr-par/sns/sns_certificate_0123456789abcdef.pem
       https://messaging.s3.xx-new.scw.cloud/xx-new/sns/sns_certificate_0123456789abcdef.pem
       https://messaging.s3.fr-par.scw.cloud/nl-ams/sns/sns_certificate_0123456789abcdef.pem
       https://messaging.s3.fr-par.scw.cloud/fr-par/other/sns_certificate_0123456789abcdef.pem].each do |url|
      it "refuses #{url} without any request" do
        envelope = fixture_envelope('signed_raw/email_queued.json').merge('SigningCertURL' => url)

        post_sns(envelope, token: token)

        expect(response).to have_http_status(:forbidden)
        expect(hook_jobs).to be_empty
        expect(a_request(:any, /.*/)).not_to have_been_made
      end
    end
  end

  context 'with an invalid token' do
    before { stub_real_certificate }

    it 'answers 404 and processes nothing for a wrong token' do
      post_sns(fixture_raw('signed_raw/email_queued.json'), token: 'wrong-token')

      expect(response).to have_http_status(:not_found)
      expect(hook_jobs).to be_empty
      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it 'answers 404 when no token is configured' do
      Facteur.scaleway_webhook_token = nil

      post_sns(fixture_raw('signed_raw/email_queued.json'), token: token)

      expect(response).to have_http_status(:not_found)
      expect(hook_jobs).to be_empty
    end

    it 'answers 404 when the configured token is blank' do
      Facteur.scaleway_webhook_token = ''

      post_sns(fixture_raw('signed_raw/email_queued.json'), token: ' ')

      expect(response).to have_http_status(:not_found)
      expect(hook_jobs).to be_empty
    end

    it 'answers 404 without the facteur_token query parameter' do
      post '/facteur/scaleway', params: fixture_raw('signed_raw/email_queued.json'),
                                headers: { 'Content-Type' => 'text/plain' }

      expect(response).to have_http_status(:not_found)
      expect(hook_jobs).to be_empty
    end

    it 'answers 404 to the former URL with the token in the path' do
      post "/facteur/scaleway/#{token}", params: fixture_raw('signed_raw/email_queued.json'),
                                         headers: { 'Content-Type' => 'text/plain' }

      expect(response).to have_http_status(:not_found)
      expect(hook_jobs).to be_empty
      expect(a_request(:any, /.*/)).not_to have_been_made
    end
  end

  describe 'request log' do
    before { stub_real_certificate }

    it 'filters the token out of the logged request' do
      log = capture_log { post_sns(fixture_raw('signed_raw/email_queued.json'), token: token) }

      expect(response).to have_http_status(:ok)
      expect(log).to include('Started POST "/facteur/scaleway?facteur_token=[FILTERED]"')
      expect(log).to match(/Parameters: \{"facteur_token" ?=> ?"\[FILTERED\]"\}/)
      expect(log).not_to include(token)
    end

    it 'adds facteur_token to the host filter_parameters once' do
      expect(Rails.application.config.filter_parameters.count { |filter| filter.to_s.include?('facteur_token') }).to eq(1)
    end
  end

  describe 'topic allow-list' do
    before { stub_test_certificate }

    it 'refuses a signed notification from another topic without downloading the certificate' do
      allow(Rails.logger).to receive(:warn)
      envelope = sign_envelope(fixture_envelope('02_notification_email_queued.json').merge('TopicArn' => foreign_topic_arn))

      post_sns(envelope, token: token)

      expect(response).to have_http_status(:forbidden)
      expect(hook_jobs).to be_empty
      expect(a_request(:any, /.*/)).not_to have_been_made
      expect(Rails.logger).to have_received(:warn).with(/Facteur.scaleway_topic_arns does not include/)
    end

    it 'refuses a signed SubscriptionConfirmation from another topic without visiting anything' do
      envelope = sign_envelope(fixture_envelope('01_subscription_confirmation.json').merge('TopicArn' => foreign_topic_arn))

      post_sns(envelope, token: token)

      expect(response).to have_http_status(:forbidden)
      expect(a_request(:any, /.*/)).not_to have_been_made
    end

    it 'refuses every message when no topic is allowed, and says which setting is missing' do
      Facteur.scaleway_topic_arns = []
      allow(Rails.logger).to receive(:warn)

      post_sns(sign_envelope(fixture_envelope('02_notification_email_queued.json')), token: token)

      expect(response).to have_http_status(:forbidden)
      expect(hook_jobs).to be_empty
      expect(a_request(:any, /.*/)).not_to have_been_made
      expect(Rails.logger).to have_received(:warn).with(/Facteur.scaleway_topic_arns is empty/)
    end

    it 'cannot be bypassed by changing the TopicArn of a signed message' do
      Facteur.scaleway_topic_arns = [SnsHelpers::TOPIC_ARN, foreign_topic_arn]
      envelope = sign_envelope(fixture_envelope('02_notification_email_queued.json')).merge('TopicArn' => foreign_topic_arn)

      post_sns(envelope, token: token)

      expect(response).to have_http_status(:forbidden)
      expect(hook_jobs).to be_empty
    end
  end

  describe 'size limits' do
    it 'answers 413 to a body over 1 MB without parsing it' do
      allow(JSON).to receive(:parse).and_call_original

      post_sns('{"Message":"' + ('a' * Facteur::WebhooksController::MAX_BODY_BYTES) + '"}', token: token)

      expect(response).to have_http_status(413)
      expect(JSON).not_to have_received(:parse)
      expect(hook_jobs).to be_empty
    end
  end

  describe 'Message' do
    before { stub_test_certificate }

    ['[{"type":"email_queued"}]', '"email_queued"', 'not json'].each do |message|
      it "ignores a notification whose Message is #{message}" do
        allow(Rails.logger).to receive(:warn)
        envelope = fixture_envelope('02_notification_email_queued.json').merge('Message' => message)

        post_sns(sign_envelope(envelope), token: token)

        expect(response).to have_http_status(:ok)
        expect(hook_jobs).to be_empty
        expect(Rails.logger).to have_received(:warn).with(/has no JSON object Message, ignored/)
      end
    end
  end

  it 'answers 400 to a body that is not JSON' do
    post_sns('not json', token: token)

    expect(response).to have_http_status(:bad_request)
    expect(hook_jobs).to be_empty
  end

  it 'answers 400 to a JSON body that is not an object' do
    post_sns('[1, 2]', token: token)

    expect(response).to have_http_status(:bad_request)
  end

  it 'answers 400 to an invalid JSON body sent as application/json' do
    post "/facteur/scaleway?facteur_token=#{token}", params: '{oops', headers: { 'Content-Type' => 'application/json' }

    expect(response).to have_http_status(:bad_request)
    expect(hook_jobs).to be_empty
  end

  describe 'SubscriptionConfirmation' do
    let(:subscribe_url) do
      'https://sns.mnq.fr-par.scaleway.com/?Action=ConfirmSubscription&TopicArn=arn:scw:sns:fr-par:project-a78227f3-3c87-4ef6-b8c1-5ca4280bf608:facteur-tem-test&Token=test-confirmation-token'
    end
    let(:confirmation) do
      fixture_envelope('01_subscription_confirmation.json')
        .merge('Token' => 'test-confirmation-token', 'SubscribeURL' => subscribe_url)
    end

    before { stub_test_certificate }

    it 'visits the SubscribeURL' do
      confirm = stub_request(:get, subscribe_url).to_return(status: 200, body: '<ConfirmSubscriptionResponse/>')

      post_sns(sign_envelope(confirmation), token: token)

      expect(response).to have_http_status(:ok)
      expect(confirm).to have_been_requested.once
      expect(hook_jobs).to be_empty
    end

    it 'answers 200 and logs when the SubscribeURL cannot be reached' do
      stub_request(:get, subscribe_url).to_timeout
      allow(Rails.logger).to receive(:warn)

      post_sns(sign_envelope(confirmation), token: token)

      expect(response).to have_http_status(:ok)
      expect(Rails.logger).to have_received(:warn).with(/Confirm subscription/)
    end

    it 'does not visit a SubscribeURL on another host, logs it and answers 200' do
      evil_url = 'https://evil.example.com/?Action=ConfirmSubscription&Token=test-confirmation-token'
      allow(Rails.logger).to receive(:warn)

      post_sns(sign_envelope(confirmation.merge('SubscribeURL' => evil_url)), token: token)

      expect(response).to have_http_status(:ok)
      expect(a_request(:get, /evil\.example\.com/)).not_to have_been_made
      expect(Rails.logger).to have_received(:warn).with(include(evil_url).and(include('Confirm subscription')))
    end

    it 'does not visit a SubscribeURL on another port' do
      port_url = subscribe_url.sub('scaleway.com/', 'scaleway.com:8443/')

      post_sns(sign_envelope(confirmation.merge('SubscribeURL' => port_url)), token: token)

      expect(response).to have_http_status(:ok)
      expect(a_request(:get, /sns\.mnq\.fr-par\.scaleway\.com/)).not_to have_been_made
    end

    it 'does not visit a SubscribeURL over http' do
      http_url = subscribe_url.sub('https://', 'http://')

      post_sns(sign_envelope(confirmation.merge('SubscribeURL' => http_url)), token: token)

      expect(response).to have_http_status(:ok)
      expect(a_request(:get, http_url)).not_to have_been_made
    end

    it 'refuses an unsigned confirmation without visiting the SubscribeURL' do
      post_sns(confirmation.merge('SigningCertURL' => SnsHelpers::TEST_CERT_URL), token: token)

      expect(response).to have_http_status(:forbidden)
      expect(a_request(:get, subscribe_url)).not_to have_been_made
    end
  end

  it 'answers 200 to an UnsubscribeConfirmation without processing it' do
    stub_test_certificate
    envelope = fixture_envelope('01_subscription_confirmation.json').merge('Type' => 'UnsubscribeConfirmation')

    post_sns(sign_envelope(envelope), token: token)

    expect(response).to have_http_status(:ok)
    expect(hook_jobs).to be_empty
  end
end
