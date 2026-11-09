# frozen_string_literal: true

Rails.application.configure do
  config.enable_reloading = true
  config.consider_all_requests_local = true
  config.server_timing = true
  config.action_mailer.delivery_method = :test
  config.action_mailer.default_url_options = { host: 'localhost' }
  config.active_support.deprecation = :log
  config.active_record.migration_error = :page_load
  config.log_level = :debug
end
