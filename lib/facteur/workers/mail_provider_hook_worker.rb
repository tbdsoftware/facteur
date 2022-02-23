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
      mail_notif = mail_notification_for_event(event_data)
      return if mail_notif.blank?

      mail_notif.events ||= []
      mail_notif.events.push(event_data.merge(provider: @provider))
      mail_notif.save!
    end

    def mail_notification_for_event(event_data)
      if @provider == :mailjet && event_data['CustomID'].present?
        MailNotification.find(event_data['CustomID'])
      elsif @provider == :sendgrid && event_data['mn_id'].present?
        MailNotification.find(event_data['mn_id'])
      end
    end
  end
end
