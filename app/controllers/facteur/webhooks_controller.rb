# frozen_string_literal: true

module Facteur
  # Not inheriting the host's ApplicationController, whose authentication would block providers
  class WebhooksController < ActionController::API
    # SendGrid batches are at most 768 KB, SNS messages at most 256 KB
    MAX_BODY_BYTES = 1.megabyte
    MAX_EVENTS = 5_000
    SENDGRID_SIGNATURE_HEADER = "X-Twilio-Email-Event-Webhook-Signature"
    SENDGRID_TIMESTAMP_HEADER = "X-Twilio-Email-Event-Webhook-Timestamp"

    def sendgrid
      return head(413) if body_too_large?
      return head(:forbidden) if !valid_sendgrid_signature?

      events = parse_sendgrid_events
      return head(:bad_request) if events.nil?
      return head(413) if events.size > MAX_EVENTS

      MailProviderHookJob.perform_async("sendgrid", events)
      head :ok
    end

    def scaleway
      return head(:not_found) if !valid_scaleway_token?
      return head(413) if body_too_large?

      envelope = parse_sns_envelope
      return head(:bad_request) if envelope.nil?
      return head(:forbidden) if !Scaleway::VerifyTopicService.new(envelope).call
      return head(:forbidden) if !Scaleway::VerifySnsSignatureService.new(envelope).call

      Scaleway::HandleSnsEnvelopeService.new(envelope).call
      head :ok
    end

    private

    def body_too_large?
      request.content_length.to_i > MAX_BODY_BYTES || request.raw_post.to_s.bytesize > MAX_BODY_BYTES
    end

    def valid_sendgrid_signature?
      Sendgrid::VerifySignatureService.new(Facteur.sendgrid_webhook_public_key, request.headers[SENDGRID_SIGNATURE_HEADER],
                                           request.headers[SENDGRID_TIMESTAMP_HEADER], request.raw_post).call
    end

    def parse_sendgrid_events
      events = JSON.parse(request.raw_post)
      events if events.is_a?(Array) && events.all?(Hash)
    rescue JSON::ParserError
      nil
    end

    def valid_scaleway_token?
      expected = Facteur.scaleway_webhook_token.to_s
      expected.present? &&
        ActiveSupport::SecurityUtils.secure_compare(expected, request.query_parameters["facteur_token"].to_s)
    end

    def parse_sns_envelope
      # SNS posts its JSON envelope as text/plain, so the raw body is parsed instead of params
      envelope = JSON.parse(request.raw_post)
      envelope if envelope.is_a?(Hash)
    rescue JSON::ParserError
      nil
    end
  end
end
