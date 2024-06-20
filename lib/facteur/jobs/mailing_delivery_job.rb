# frozen_string_literal: true

module Facteur
  # Handles delivery of mailings
  class MailingDeliveryJob
    include Sidekiq::Job

    def perform(mailing_id)
      @mailing_id = ::Facteur::Mailing.find(mailing_id)
      @mailing_id.deliver
    end
  end
end
