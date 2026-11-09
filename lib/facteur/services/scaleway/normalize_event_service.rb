# frozen_string_literal: true

module Facteur
  module Scaleway
    # Turns a Scaleway TEM webhook event into a Facteur event, or nil when the type is not tracked
    class NormalizeEventService
      EVENTS = {
        'email_queued' => 'processed',
        'email_delivered' => 'delivered',
        'email_deferred' => 'deferred',
        'email_dropped' => 'dropped',
        'email_spam' => 'dropped',
        'email_mailbox_not_found' => 'dropped',
        'email_blocklisted' => 'dropped'
      }.freeze
      MAILING_ID_HEADER = 'X-Facteur-Mailing-Id'
      REASON_KEYS = %w[email_response_message email_error blocklist_reason].freeze

      def initialize(raw)
        @raw = raw
      end

      def call
        event = EVENTS[@raw['type']]
        return if event.nil?

        {
          mailing_id: mailing_id,
          event: {
            'event' => event,
            'type' => @raw['type'],
            'timestamp' => timestamp,
            'reason' => reason,
            'provider' => 'scaleway',
            'provider_event_id' => @raw['id'],
            'provider_message_id' => @raw['email_id'],
            'payload' => @raw
          }
        }
      end

      private

      def mailing_id
        headers = @raw['email_headers'].is_a?(Array) ? @raw['email_headers'] : []
        header = headers.find { |h| h.is_a?(Hash) && h['key'].to_s.casecmp?(MAILING_ID_HEADER) }
        header && header['value']
      end

      def timestamp
        Time.zone.iso8601(@raw['created_at'].to_s).to_f
      rescue ArgumentError
        Time.current.to_f
      end

      def reason
        REASON_KEYS.map { |key| @raw[key] }.find(&:present?)&.to_s&.strip
      end
    end
  end
end
