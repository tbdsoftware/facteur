# frozen_string_literal: true

module Facteur
  # Records the events received from a mail provider webhook on their mailing
  class MailProviderHookService
    NORMALIZERS = {
      'sendgrid' => ::Facteur::Sendgrid::NormalizeEventService,
      'scaleway' => ::Facteur::Scaleway::NormalizeEventService
    }.freeze
    # Rails would cast "4-abc" to 4 and attach the event to the wrong mailing
    MAILING_ID_FORMAT = /\A\d+\z/

    def initialize(provider, params)
      @provider = provider.to_s
      @params = params
    end

    def call
      normalizer = NORMALIZERS[@provider]
      return log(:warn, "unknown provider #{@provider.inspect}, events ignored") if normalizer.nil?

      Array.wrap(@params).each { |raw| handle_event(normalizer, raw) }
    end

    private

    def handle_event(normalizer, raw)
      return log(:info, 'blank event ignored') if !raw.is_a?(Hash) || raw.blank?

      normalized = normalizer.new(raw).call
      return log(:info, "untracked event #{(raw['type'] || raw['event']).inspect} ignored") if normalized.nil?

      event = normalized[:event]
      mailing = find_mailing(normalized[:mailing_id])
      if mailing.nil?
        return log(:info, "no mailing for event #{event['provider_event_id'].inspect} " \
                          "(mailing id #{normalized[:mailing_id].inspect}), ignored")
      end

      record_event(mailing, event)
    end

    def find_mailing(mailing_id)
      return if !mailing_id.to_s.match?(MAILING_ID_FORMAT)

      ::Facteur::Mailing.find_by(id: mailing_id.to_s)
    end

    def record_event(mailing, event)
      mailing.with_lock do
        if duplicate?(mailing, event)
          log(:info, "event #{event['provider_event_id']} already recorded on #{mailing}, ignored")
        else
          mailing.events = (mailing.events || []) + [event]
          message_id = event['provider_message_id']
          mailing.provider_message_ids = (mailing.provider_message_ids + [message_id]).uniq if message_id.present?
          mailing.save!
        end
      end
    end

    def duplicate?(mailing, event)
      event_id = event['provider_event_id']
      event_id.present? && (mailing.events || []).any? { |e| e['provider_event_id'] == event_id }
    end

    def log(level, message)
      Rails.logger.public_send(level, "[Facteur] #{@provider} webhook: #{message}")
      nil
    end
  end
end
