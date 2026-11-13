# frozen_string_literal: true

require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_job/railtie'
require 'active_record/railtie'
require 'action_controller/railtie'
require 'action_mailer/railtie'
require 'action_view/railtie'

# Deprecations hit while Bundler.require loads the gems (facteur's engine included) come before
# `config.active_support.deprecation = :raise` applies
[ActiveSupport.deprecator, ActiveRecord.deprecator].each { |deprecator| deprecator.behavior = :raise } if Rails.env.test?

Bundler.require(*Rails.groups)
require 'facteur'

module Dummy
  class Application < Rails::Application
    config.load_defaults 7.1
    # load_defaults 7.1 sets it to true, a value deprecated in Rails 8.0; Rails 8.1 deprecates the setting itself
    config.active_support.to_time_preserves_timezone = :zone if Rails::VERSION::STRING.start_with?('8.0.')
    config.root = File.expand_path('..', __dir__)
    config.eager_load = false
    config.active_record.schema_format = :ruby
  end
end
