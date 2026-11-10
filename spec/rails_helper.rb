# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require_relative 'dummy/config/environment'
abort('The Rails environment is running in production mode!') if Rails.env.production?

require 'rspec/rails'
require 'sidekiq/testing'
require 'webmock/rspec'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |file| require file }

ActiveRecord::Migration.maintain_test_schema!

Sidekiq::Testing.fake!
Sidekiq.logger.level = Logger::WARN
WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed

  config.before do
    Sidekiq::Job.clear_all
    ActionMailer::Base.deliveries.clear
    Facteur.provider = :sendgrid
    Facteur.scaleway_webhook_token = nil
    Facteur.store_body = true
    Facteur::Scaleway::VerifySnsSignatureService::CERTIFICATES.clear
  end
end
