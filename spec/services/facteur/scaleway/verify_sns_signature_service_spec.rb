# frozen_string_literal: true

RSpec.describe Facteur::Scaleway::VerifySnsSignatureService do
  def verify(envelope)
    described_class.new(envelope).call
  end

  let(:notification) { fixture_envelope('02_notification_email_queued.json') }

  before { travel_to_fixtures_time }

  context 'with real Scaleway payloads' do
    before { stub_real_certificate }

    %w[signed_raw/email_queued.json signed_raw/email_dropped.json].each do |fixture|
      it "accepts #{fixture} (SignatureVersion 1, SHA1)" do
        expect(verify(fixture_envelope(fixture))).to be(true)
      end
    end

    it 'rejects a payload whose Message was altered' do
      envelope = fixture_envelope('signed_raw/email_queued.json')
      envelope['Message'] = envelope['Message'].sub('email_queued', 'email_queuee')

      expect(verify(envelope)).to be(false)
    end

    it 'rejects a SHA1 signature announced as SignatureVersion 2' do
      envelope = fixture_envelope('signed_raw/email_queued.json').merge('SignatureVersion' => '2')

      expect(verify(envelope)).to be(false)
    end
  end

  context 'with payloads signed by the test key' do
    before { stub_test_certificate }

    it 'accepts SignatureVersion 2 (SHA256)' do
      expect(verify(sign_envelope(notification, version: '2'))).to be(true)
    end

    it 'accepts a SubscriptionConfirmation' do
      expect(verify(sign_envelope(fixture_envelope('01_subscription_confirmation.json')))).to be(true)
    end

    it 'rejects an unknown SignatureVersion without fetching the certificate' do
      envelope = sign_envelope(notification).merge('SignatureVersion' => '3')

      expect(verify(envelope)).to be(false)
      expect(a_request(:get, SnsHelpers::TEST_CERT_URL)).not_to have_been_made
    end

    it 'rejects a payload with a missing signed field' do
      envelope = sign_envelope(notification).except('Timestamp')

      expect(verify(envelope)).to be(false)
    end

    it 'rejects a payload without Signature' do
      expect(verify(sign_envelope(notification).except('Signature'))).to be(false)
    end

    it 'rejects a garbage signature' do
      expect(verify(sign_envelope(notification).merge('Signature' => 'bm90IGEgc2lnbmF0dXJl'))).to be(false)
    end

    it 'includes Subject in the signed string when present' do
      envelope = sign_envelope(notification.merge('Subject' => 'Facteur'))

      expect(verify(envelope)).to be(true)
      expect(verify(envelope.except('Subject'))).to be(false)
      expect(verify(envelope.merge('Subject' => 'Other'))).to be(false)
    end

    it 'fetches the certificate once for several verifications' do
      2.times { expect(verify(sign_envelope(notification))).to be(true) }

      expect(a_request(:get, SnsHelpers::TEST_CERT_URL)).to have_been_made.once
    end

    it 'rejects when the certificate cannot be downloaded' do
      stub_request(:get, SnsHelpers::TEST_CERT_URL).to_return(status: 500)

      expect(verify(sign_envelope(notification))).to be(false)
    end

    it 'downloads the certificate again after a failed download' do
      stub_request(:get, SnsHelpers::TEST_CERT_URL)
        .to_return({ status: 500 }, { status: 200, body: SnsHelpers::TEST_CERT.to_pem })

      expect(verify(sign_envelope(notification))).to be(false)
      expect(verify(sign_envelope(notification))).to be(true)
      expect(a_request(:get, SnsHelpers::TEST_CERT_URL)).to have_been_made.twice
    end

    it 'rejects when the certificate download times out' do
      stub_request(:get, SnsHelpers::TEST_CERT_URL).to_timeout

      expect(verify(sign_envelope(notification))).to be(false)
    end

    it 'rejects when the certificate is not a PEM' do
      stub_request(:get, SnsHelpers::TEST_CERT_URL).to_return(status: 200, body: 'not a certificate')

      expect(verify(sign_envelope(notification))).to be(false)
    end

    {
      'a Timestamp older than 6 hours' => 6.hours + 1.second,
      'a Timestamp more than 5 minutes ahead' => -(5.minutes + 1.second)
    }.each do |name, age|
      it "rejects #{name} without fetching the certificate" do
        envelope = sign_envelope(notification.merge('Timestamp' => (Time.current - age).utc.iso8601))

        expect(verify(envelope)).to be(false)
        expect(a_request(:get, SnsHelpers::TEST_CERT_URL)).not_to have_been_made
      end
    end

    it 'accepts a Timestamp just under 6 hours old or up to 5 minutes ahead' do
      [6.hours - 1.second, -5.minutes].each do |age|
        expect(verify(sign_envelope(notification.merge('Timestamp' => (Time.current - age).utc.iso8601)))).to be(true)
      end
    end

    it 'rejects an unparsable Timestamp' do
      expect(verify(sign_envelope(notification.merge('Timestamp' => 'yesterday')))).to be(false)
    end

    it 'rejects the real payloads replayed a day later' do
      stub_real_certificate
      travel 1.day

      expect(verify(fixture_envelope('signed_raw/email_queued.json'))).to be(false)
    end
  end

  describe 'certificate checks' do
    it 'rejects a certificate whose CN is not the SNS host of the region' do
      stub_test_certificate(SnsHelpers.build_certificate(common_name: 'sns.mnq.nl-ams.scaleway.com'))

      expect(verify(sign_envelope(notification))).to be(false)
    end

    it 'rejects a certificate that is not issued for Scaleway SNS' do
      stub_test_certificate(SnsHelpers.build_certificate(common_name: 'evil.example.com'))

      expect(verify(sign_envelope(notification))).to be(false)
    end

    it 'rejects an expired certificate' do
      stub_test_certificate(SnsHelpers.build_certificate(not_after: 1.day.ago))

      expect(verify(sign_envelope(notification))).to be(false)
    end

    it 'rejects a certificate that is not valid yet' do
      stub_test_certificate(SnsHelpers.build_certificate(not_before: 1.day.from_now))

      expect(verify(sign_envelope(notification))).to be(false)
    end

    it 'rejects a cached certificate once it has expired' do
      stub_test_certificate(SnsHelpers.build_certificate(not_after: 1.hour.from_now))
      expect(verify(sign_envelope(notification))).to be(true)

      travel 2.hours

      expect(verify(sign_envelope(notification.merge('Timestamp' => Time.current.utc.iso8601)))).to be(false)
    end
  end

  describe 'certificate cache' do
    let(:cache) { described_class::CERTIFICATES }

    it 'never holds more than MAX_CACHED_CERTIFICATES certificates' do
      urls = Array.new(described_class::MAX_CACHED_CERTIFICATES + 3) do |index|
        format('https://messaging.s3.fr-par.scw.cloud/fr-par/sns/sns_certificate_%040x.pem', index)
      end
      urls.each { |url| stub_request(:get, url).to_return(status: 200, body: SnsHelpers::TEST_CERT.to_pem) }

      urls.each do |url|
        expect(verify(sign_envelope(notification, cert_url: url))).to be(true)
        expect(cache.size).to be <= described_class::MAX_CACHED_CERTIFICATES
      end
      expect(cache.keys).to include(urls.last)
    end
  end

  context 'with an untrusted SigningCertURL' do
    [
      'https://evil.example.com/x.pem',
      'http://messaging.s3.fr-par.scw.cloud/fr-par/sns/sns_certificate_0123456789abcdef.pem',
      'https://messaging.s3.fr-par.scw.cloud.evil.example.com/x.pem',
      'https://messaging.s3.fr-par.scw.cloud@evil.example.com/x.pem',
      'https://messaging.s3.fr-par.scw.cloud:8443/fr-par/sns/sns_certificate_0123456789abcdef.pem',
      'https://messaging.s3.xx-new.scw.cloud/xx-new/sns/sns_certificate_0123456789abcdef.pem',
      'https://messaging.s3.fr-par.scw.cloud/nl-ams/sns/sns_certificate_0123456789abcdef.pem',
      'https://messaging.s3.nl-ams.scw.cloud/fr-par/sns/sns_certificate_0123456789abcdef.pem',
      'https://messaging.s3.fr-par.scw.cloud/fr-par/other/sns_certificate_0123456789abcdef.pem',
      'https://messaging.s3.fr-par.scw.cloud/fr-par/sns/attacker.pem',
      'https://messaging.s3.fr-par.scw.cloud/fr-par/sns/sns_certificate_0123456789abcdef.pem?x=1',
      'https://messaging.s3.fr-par.scw.cloud/fr-par/sns/../sns/sns_certificate_0123456789abcdef.pem',
      'not a url'
    ].each do |url|
      it "rejects #{url} without any HTTP request" do
        envelope = sign_envelope(notification).merge('SigningCertURL' => url)

        expect(verify(envelope)).to be(false)
        expect(a_request(:any, /.*/)).not_to have_been_made
      end
    end
  end

  it 'accepts the 3 Scaleway regions, each with its own certificate' do
    described_class::REGIONS.each do |region|
      url = "https://messaging.s3.#{region}.scw.cloud/#{region}/sns/sns_certificate_0123456789abcdef.pem"
      certificate = SnsHelpers.build_certificate(common_name: "sns.mnq.#{region}.scaleway.com")
      stub_request(:get, url).to_return(status: 200, body: certificate.to_pem)

      expect(verify(sign_envelope(notification, cert_url: url))).to be(true)
    end
  end
end
