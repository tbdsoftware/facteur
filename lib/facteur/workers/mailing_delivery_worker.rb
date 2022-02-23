# frozen_string_literal: true

module Facteur
  # Handles delivery of mailings
  class MailingDeliveryWorker
    include Sidekiq::Worker

    def perform(mail_notif_id)
      @mail_notif = MailNotification.find(mail_notif_id)
      @mail_notif.deliver
    end
  end
end
