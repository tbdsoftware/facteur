# frozen_string_literal: true

module SnsHelpers
  FIXTURES_DIR = File.expand_path('../fixtures/scaleway', __dir__)
  REAL_CERT_URL = 'https://messaging.s3.fr-par.scw.cloud/fr-par/sns/sns_certificate_0c099e58091dfc9a2d686099b0fa5eae6ec43ef9.pem'
  TEST_CERT_URL = 'https://messaging.s3.fr-par.scw.cloud/fr-par/sns/facteur_test_certificate.pem'
  TEST_KEY = OpenSSL::PKey::RSA.new(2048)
  TEST_CERT = OpenSSL::X509::Certificate.new.tap do |cert|
    cert.version = 2
    cert.serial = 1
    cert.subject = cert.issuer = OpenSSL::X509::Name.parse('/CN=facteur-test-sns')
    cert.public_key = TEST_KEY.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    cert.sign(TEST_KEY, OpenSSL::Digest.new('SHA256'))
  end
  NOTIFICATION_KEYS = %w[Message MessageId Subject Timestamp TopicArn Type].freeze
  SUBSCRIPTION_KEYS = %w[Message MessageId SubscribeURL Timestamp Token TopicArn Type].freeze

  def fixture_raw(name)
    File.read(File.join(FIXTURES_DIR, name))
  end

  def fixture_envelope(name)
    JSON.parse(fixture_raw(name))
  end

  def stub_real_certificate
    stub_request(:get, REAL_CERT_URL).to_return(status: 200, body: fixture_raw('signed_raw/scaleway_sns_cert.pem'))
  end

  def stub_test_certificate
    stub_request(:get, TEST_CERT_URL).to_return(status: 200, body: TEST_CERT.to_pem)
  end

  def sns_canonical_string(envelope)
    keys = envelope['Type'] == 'Notification' ? NOTIFICATION_KEYS : SUBSCRIPTION_KEYS
    keys.filter_map { |key| "#{key}\n#{envelope[key]}\n" if envelope.key?(key) }.join
  end

  def sign_envelope(envelope, version: '1')
    digest = version == '2' ? 'SHA256' : 'SHA1'
    signed = envelope.merge('SigningCertURL' => TEST_CERT_URL, 'SignatureVersion' => version)
    signature = TEST_KEY.sign(OpenSSL::Digest.new(digest), sns_canonical_string(signed))
    signed.merge('Signature' => Base64.strict_encode64(signature))
  end

  def with_mailing_id(envelope, mailing_id)
    message = JSON.parse(envelope['Message'])
    return envelope if message['email_headers'].nil?

    message['email_headers'] = message['email_headers'].map do |header|
      header['key'].casecmp?('X-Facteur-Mailing-Id') ? header.merge('value' => mailing_id.to_s) : header
    end
    envelope.merge('Message' => message.to_json)
  end

  def signed_event_envelope(fixture, mailing_id)
    sign_envelope(with_mailing_id(fixture_envelope(fixture), mailing_id))
  end

  def event_payload(fixture, mailing_id = nil)
    envelope = fixture_envelope(fixture)
    envelope = with_mailing_id(envelope, mailing_id) if mailing_id
    JSON.parse(envelope['Message'])
  end

  def post_sns(body, token:)
    body = body.to_json if !body.is_a?(String)
    post "/facteur/scaleway/#{token}", params: body, headers: { 'Content-Type' => 'text/plain' }
  end
end

RSpec.configure do |config|
  config.include SnsHelpers
end
