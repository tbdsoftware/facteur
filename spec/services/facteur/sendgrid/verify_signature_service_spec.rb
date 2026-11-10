# frozen_string_literal: true

RSpec.describe Facteur::Sendgrid::VerifySignatureService do
  let(:payload) { '[{"event":"processed","mn_id":"1"}]' }
  let(:timestamp) { '1794193288' }
  let(:signature) { sendgrid_signature(payload, timestamp) }

  def verify(public_key: SendgridHelpers::PUBLIC_KEY, signature: self.signature, timestamp: self.timestamp,
             payload: self.payload)
    described_class.new(public_key, signature, timestamp, payload).call
  end

  it 'accepts a payload signed with the private key of the public key' do
    expect(verify).to be(true)
  end

  it 'verifies the raw bytes of a non-ASCII payload' do
    payload = '[{"event":"processed","subject":"Réinitialisation"}]'.b

    expect(verify(payload: payload, signature: sendgrid_signature(payload, timestamp))).to be(true)
  end

  it 'rejects a payload with one character changed' do
    expect(verify(payload: payload.sub('processed', 'processee'))).to be(false)
  end

  it 'rejects another timestamp' do
    expect(verify(timestamp: '1794193289')).to be(false)
  end

  it 'rejects a payload signed by another key' do
    other_key = OpenSSL::PKey::EC.generate('prime256v1')

    expect(verify(signature: sendgrid_signature(payload, timestamp, key: other_key))).to be(false)
  end

  it 'rejects a missing signature or timestamp' do
    expect(verify(signature: nil)).to be(false)
    expect(verify(signature: '')).to be(false)
    expect(verify(timestamp: nil)).to be(false)
  end

  it 'rejects a garbage signature' do
    expect(verify(signature: 'bm90IGEgc2lnbmF0dXJl')).to be(false)
  end

  it 'rejects a malformed public key' do
    expect(verify(public_key: 'bm90IGEga2V5')).to be(false)
    expect(verify(public_key: Base64.strict_encode64(OpenSSL::PKey::RSA.new(2048).public_to_der))).to be(false)
  end

  it 'logs why it rejects a payload' do
    allow(Rails.logger).to receive(:warn)

    verify(signature: nil)

    expect(Rails.logger).to have_received(:warn).with(/SendGrid webhook signature rejected/)
  end
end
