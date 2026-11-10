# frozen_string_literal: true

module Facteur
  class MailProviderHookJob
    include Sidekiq::Job

    def perform(provider, params)
      ::Facteur::MailProviderHookService.new(provider, params).call
    end
  end
end
