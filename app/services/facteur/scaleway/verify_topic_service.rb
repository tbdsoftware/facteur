# frozen_string_literal: true

module Facteur
  module Scaleway
    class VerifyTopicService
      def initialize(envelope)
        @envelope = envelope
      end

      def call
        topic_arns = Array(Facteur.scaleway_topic_arns)
        return true if topic_arns.include?(@envelope["TopicArn"])

        reason = topic_arns.empty? ? "is empty" : "does not include #{@envelope['TopicArn'].to_s.truncate(200).inspect}"
        Rails.logger.warn("[Facteur] Scaleway SNS #{@envelope['Type']} #{@envelope['MessageId']} refused: " \
                          "Facteur.scaleway_topic_arns #{reason}")
        false
      end
    end
  end
end
