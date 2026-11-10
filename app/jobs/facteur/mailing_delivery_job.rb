# frozen_string_literal: true

module Facteur
  class MailingDeliveryJob
    include Sidekiq::Job

    def perform(mailing_id)
      mailing = ::Facteur::Mailing.find(mailing_id)
      ::Facteur::MailingDeliveryService.new(mailing).call
    end
  end
end
