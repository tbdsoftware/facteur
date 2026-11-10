# frozen_string_literal: true

module Facteur
  # Not inheriting the host's ApplicationController, whose authentication would block providers
  class WebhooksController < ActionController::API
    def sendgrid
      body = request.raw_post
      json_params = body.presence && ActiveSupport::JSON.decode(body)
      MailProviderHookJob.perform_async("sendgrid", json_params)

      head :ok
    end

    def scaleway
      return head(:not_found) if !valid_scaleway_token?

      envelope = parse_sns_envelope
      return head(:bad_request) if envelope.nil?
      return head(:forbidden) if !Scaleway::VerifySnsSignatureService.new(envelope).call

      Scaleway::HandleSnsEnvelopeService.new(envelope).call
      head :ok
    end

    private

    def valid_scaleway_token?
      expected = Facteur.scaleway_webhook_token.to_s
      expected.present? &&
        ActiveSupport::SecurityUtils.secure_compare(expected, request.path_parameters[:token].to_s)
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
