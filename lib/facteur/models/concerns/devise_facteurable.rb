# frozen_string_literal: true

module Facteur
  # When included on a devise model, this concern makes devise send emails via our Mailing model
  module DeviseFacteurable
    extend ActiveSupport::Concern

    included do
      after_commit :send_pending_devise_notifications
    end

    protected

    def send_devise_notification(notification, *args)
      # If the record is new or changed then delay the
      # delivery until the after_commit callback otherwise
      # send now because after_commit will not be called.
      # For Rails < 6 use `changed?` instead of `saved_changes?`.
      if new_record? || changed?
        pending_devise_notifications << [notification, args]
      else
        create_devise_mailing(notification, *args)
      end
    end

    private

    def send_pending_devise_notifications
      pending_devise_notifications.each do |notification, args|
        create_devise_mailing(notification, *args)
      end

      # Empty the pending notifications array because the
      # after_commit hook can be called multiple times which
      # could cause multiple emails to be sent.
      pending_devise_notifications.clear
    end

    def pending_devise_notifications
      @pending_devise_notifications ||= []
    end

    def create_devise_mailing(notification, *args)
      Mailing.create!(resource: self,
                      mailer_klass: devise_mailer,
                      mailer_method: notification,
                      mailer_params: args)
    end
  end
end
