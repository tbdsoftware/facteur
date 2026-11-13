# frozen_string_literal: true

ENV['RAILS_ENV'] ||= 'test'

require_relative 'dummy/config/environment'
abort('The Rails environment is running in production mode!') if Rails.env.production?

require 'rspec/rails'
require 'webmock/rspec'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |file| require file }

ActiveRecord::Migration.maintain_test_schema!

# Sidekiq 8.1 deprecates sidekiq/testing for Sidekiq.testing!, which Sidekiq 7 doesn't have
if Sidekiq.respond_to?(:testing!)
  Sidekiq.testing!(:fake)
else
  require 'sidekiq/testing'
  Sidekiq::Testing.fake!
end
Sidekiq.logger.level = Logger::WARN
WebMock.disable_net_connect!(allow_localhost: true)

RSpec.configure do |config|
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
  config.disable_monkey_patching!
  config.include ActiveSupport::Testing::TimeHelpers
  config.order = :random
  Kernel.srand config.seed

  config.before do
    Sidekiq::Job.clear_all
    ActionMailer::Base.deliveries.clear
    Facteur.provider = :sendgrid
    Facteur.sendgrid_webhook_public_key = nil
    Facteur.scaleway_webhook_token = nil
    Facteur.scaleway_topic_arns = []
    Facteur.store_body = true
    Facteur::Scaleway::VerifySnsSignatureService::CERTIFICATES.clear
  end

  config.after { travel_back }
end
