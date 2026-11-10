# frozen_string_literal: true

module SendgridHelpers
  SIGNING_KEY = OpenSSL::PKey::EC.generate('prime256v1')
  PUBLIC_KEY = Base64.strict_encode64(SIGNING_KEY.public_to_der)

  def sendgrid_signature(payload, timestamp, key: SIGNING_KEY)
    Base64.strict_encode64(key.sign(OpenSSL::Digest.new('SHA256'), timestamp + payload))
  end

  def post_sendgrid(payload, timestamp: Time.current.to_i.to_s, signature: sendgrid_signature(payload, timestamp))
    headers = { 'Content-Type' => 'application/json' }
    headers['X-Twilio-Email-Event-Webhook-Signature'] = signature if signature
    headers['X-Twilio-Email-Event-Webhook-Timestamp'] = timestamp if timestamp
    post '/facteur/sendgrid', params: payload, headers: headers
  end
end

RSpec.configure do |config|
  config.include SendgridHelpers
end
