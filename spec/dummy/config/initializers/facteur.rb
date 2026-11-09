# frozen_string_literal: true

Facteur.configure do |config|
  config.provider = ENV.fetch('FACTEUR_PROVIDER', 'sendgrid').to_sym
  config.scaleway_webhook_token = ENV['FACTEUR_SCALEWAY_TOKEN'].presence
end

# Lets the dummy app run as a server without Redis
if Rails.env.development? && ENV['FACTEUR_INLINE_JOBS'] == '1'
  require 'sidekiq/testing'
  Sidekiq::Testing.inline!
end
