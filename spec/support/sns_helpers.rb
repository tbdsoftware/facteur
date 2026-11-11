# frozen_string_literal: true

module SnsHelpers
  FIXTURES_DIR = File.expand_path('../fixtures/scaleway', __dir__)
  REAL_CERT_URL = 'https://messaging.s3.fr-par.scw.cloud/fr-par/sns/sns_certificate_0c099e58091dfc9a2d686099b0fa5eae6ec43ef9.pem'
  TEST_CERT_URL = 'https://messaging.s3.fr-par.scw.cloud/fr-par/sns/sns_certificate_0123456789abcdef.pem'
  TOPIC_ARN = 'arn:scw:sns:fr-par:project-a78227f3-3c87-4ef6-b8c1-5ca4280bf608:facteur-tem-test'
  # The fixtures were signed on 09/11/2026 and SNS messages older than 6 hours are refused
  FIXTURES_TIME = Time.utc(2026, 11, 9, 3, 5)
  TEST_KEY = OpenSSL::PKey::RSA.new(2048)

  def self.build_certificate(common_name: 'sns.mnq.fr-par.scaleway.com', not_before: Time.utc(2026, 1, 1),
                             not_after: Time.utc(2036, 1, 1))
    OpenSSL::X509::Certificate.new.tap do |cert|
      cert.version = 2
      cert.serial = 1
      cert.subject = OpenSSL::X509::Name.parse("/CN=#{common_name}")
      cert.issuer = OpenSSL::X509::Name.parse('/CN=Scaleway MnQ')
      cert.public_key = TEST_KEY.public_key
      cert.not_before = not_before
      cert.not_after = not_after
      cert.sign(TEST_KEY, OpenSSL::Digest.new('SHA256'))
    end
  end

  TEST_CERT = build_certificate
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

  def stub_test_certificate(certificate = TEST_CERT)
    stub_request(:get, TEST_CERT_URL).to_return(status: 200, body: certificate.to_pem)
  end

  def travel_to_fixtures_time
    travel_to FIXTURES_TIME
  end

  def sns_canonical_string(envelope)
    keys = envelope['Type'] == 'Notification' ? NOTIFICATION_KEYS : SUBSCRIPTION_KEYS
    keys.filter_map { |key| "#{key}\n#{envelope[key]}\n" if envelope.key?(key) }.join
  end

  def sign_envelope(envelope, version: '1', cert_url: TEST_CERT_URL)
    digest = version == '2' ? 'SHA256' : 'SHA1'
    signed = envelope.merge('SigningCertURL' => cert_url, 'SignatureVersion' => version)
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
    post "/facteur/scaleway?facteur_token=#{CGI.escape(token)}", params: body, headers: { 'Content-Type' => 'text/plain' }
  end
end

RSpec.configure do |config|
  config.include SnsHelpers
end
