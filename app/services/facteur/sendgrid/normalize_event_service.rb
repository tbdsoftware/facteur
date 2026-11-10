# frozen_string_literal: true

module Facteur
  module Sendgrid
    class NormalizeEventService
      def initialize(raw)
        @raw = raw
      end

      def call
        return if @raw["event"].blank?

        {
          mailing_id: @raw["mn_id"],
          event: @raw.merge(
            "event" => @raw["event"],
            "type" => @raw["type"],
            "timestamp" => @raw["timestamp"].to_f,
            "reason" => @raw["reason"],
            "provider" => "sendgrid",
            "provider_event_id" => @raw["sg_event_id"],
            "provider_message_id" => @raw["sg_message_id"],
            "payload" => @raw
          )
        }
      end
    end
  end
end
