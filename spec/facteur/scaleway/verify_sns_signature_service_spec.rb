# frozen_string_literal: true

RSpec.describe Facteur::Scaleway::VerifySnsSignatureService do
  def verify(envelope)
    described_class.new(envelope).call
  end

  let(:notification) { fixture_envelope('02_notification_email_queued.json') }

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

    it 'rejects when the certificate download times out' do
      stub_request(:get, SnsHelpers::TEST_CERT_URL).to_timeout

      expect(verify(sign_envelope(notification))).to be(false)
    end

    it 'rejects when the certificate is not a PEM' do
      stub_request(:get, SnsHelpers::TEST_CERT_URL).to_return(status: 200, body: 'not a certificate')

      expect(verify(sign_envelope(notification))).to be(false)
    end
  end

  context 'with an untrusted SigningCertURL' do
    [
      'https://evil.example.com/x.pem',
      'http://messaging.s3.fr-par.scw.cloud/fr-par/sns/facteur_test_certificate.pem',
      'https://messaging.s3.fr-par.scw.cloud.evil.example.com/x.pem',
      'https://messaging.s3.fr-par.scw.cloud@evil.example.com/x.pem',
      'not a url'
    ].each do |url|
      it "rejects #{url} without any HTTP request" do
        envelope = sign_envelope(notification).merge('SigningCertURL' => url)

        expect(verify(envelope)).to be(false)
        expect(a_request(:any, /.*/)).not_to have_been_made
      end
    end
  end
end
