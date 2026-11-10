# frozen_string_literal: true

Rails.application.configure do
  config.enable_reloading = false
  config.consider_all_requests_local = true
  config.action_controller.allow_forgery_protection = false
  config.action_dispatch.show_exceptions = :rescuable
  config.action_mailer.delivery_method = :test
  config.action_mailer.default_url_options = { host: 'localhost' }
  config.active_support.deprecation = :raise
end
