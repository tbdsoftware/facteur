# frozen_string_literal: true

module Facteur
  module Scaleway
    class HandleSnsEnvelopeService
      def initialize(envelope)
        @envelope = envelope
      end

      def call
        Rails.logger.info("[Facteur] Scaleway SNS #{@envelope['Type']} #{@envelope['MessageId']} signature verified")
        case @envelope['Type']
        when 'SubscriptionConfirmation'
          ::Facteur::Scaleway::ConfirmSubscriptionService.new(@envelope).call
        when 'Notification'
          enqueue_notification
        else
          Rails.logger.info("[Facteur] Scaleway SNS #{@envelope['Type'].inspect} message #{@envelope['MessageId']} ignored")
        end
      end

      private

      def enqueue_notification
        ::Facteur::MailProviderHookJob.perform_async('scaleway', JSON.parse(@envelope['Message'].to_s))
      rescue JSON::ParserError
        Rails.logger.warn("[Facteur] Scaleway SNS notification #{@envelope['MessageId']} has no JSON Message, ignored")
      end
    end
  end
end
