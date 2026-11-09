# frozen_string_literal: true

module Facteur
  # Job responsible for treating inputs from sendgrid/scaleway
  class MailProviderHookJob
    include Sidekiq::Job

    def perform(provider, params)
      ::Facteur::MailProviderHookService.new(provider, params).call
    end
  end
end
