# frozen_string_literal: true

module Facteur
  module Scaleway
    class HandleSnsEnvelopeService
      def initialize(envelope)
        @envelope = envelope
      end

      def call
        Rails.logger.info("[Facteur] Scaleway SNS #{@envelope['Type']} #{@envelope['MessageId']} signature verified")
        case @envelope["Type"]
        when "SubscriptionConfirmation"
          ::Facteur::Scaleway::ConfirmSubscriptionService.new(@envelope).call
        when "Notification"
          enqueue_notification
        else
          Rails.logger.info("[Facteur] Scaleway SNS #{@envelope['Type'].inspect} message #{@envelope['MessageId']} ignored")
        end
      end

      private

      def enqueue_notification
        event = parse_message
        if event.nil?
          Rails.logger.warn("[Facteur] Scaleway SNS notification #{@envelope['MessageId']} has no JSON object Message, ignored")
        else
          ::Facteur::MailProviderHookJob.perform_async("scaleway", event)
        end
      end

      def parse_message
        event = JSON.parse(@envelope["Message"].to_s)
        event if event.is_a?(Hash)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
