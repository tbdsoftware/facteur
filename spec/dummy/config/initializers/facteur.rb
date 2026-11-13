# frozen_string_literal: true

Facteur.configure do |config|
  config.provider = ENV.fetch('FACTEUR_PROVIDER', 'sendgrid').to_sym
  config.webhooks = ENV.fetch('FACTEUR_WEBHOOKS', 'sendgrid,scaleway').split(',').map(&:strip).compact_blank.map(&:to_sym)
  config.sendgrid_webhook_public_key = ENV['FACTEUR_SENDGRID_PUBLIC_KEY'].presence
  config.scaleway_webhook_token = ENV['FACTEUR_SCALEWAY_TOKEN'].presence
  config.scaleway_topic_arns = ENV.fetch('FACTEUR_SCALEWAY_TOPIC_ARNS', '').split(',').map(&:strip).compact_blank
end

# Lets the dummy app run as a server without Redis
if Rails.env.development? && ENV['FACTEUR_INLINE_JOBS'] == '1'
  if Sidekiq.respond_to?(:testing!)
    Sidekiq.testing!(:inline)
  else
    require 'sidekiq/testing'
    Sidekiq::Testing.inline!
  end
end
