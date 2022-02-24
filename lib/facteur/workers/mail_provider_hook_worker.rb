# frozen_string_literal: true

module Facteur
  # Worker responsible for treating inputs from mailjet/sendgrid
  class MailProviderHookWorker
    include Sidekiq::Worker

    def perform(provider, params)
      @provider = provider.to_sym
      if params.is_a? Array
        params.each do |event_data|
          handle_event(event_data)
        end
      else
        handle_event(params)
      end
    end

    def handle_event(event_data)
      mailing = mailing_for_event(event_data)
      return if mailing.blank?

      mailing.events ||= []
      mailing.events.push(event_data.merge(provider: @provider))
      mailing.save!
    end

    def mailing_for_event(event_data)
      return if event_data.blank?

      if @provider == :mailjet && event_data['CustomID'].present?
        ::Facteur::Mailing.find(event_data['CustomID'])
      elsif @provider == :sendgrid && event_data['mn_id'].present?
        ::Facteur::Mailing.find(event_data['mn_id'])
      end
    end
  end
end
