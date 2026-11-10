# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

gem 'oj'
# The CI also runs the suite on Rails 7.2 and 8.0, see gemfiles/
gem 'rails', "~> #{ENV.fetch('RAILS_VERSION', '7.1.3')}"
gem 'sidekiq', '~> 7.2'

group :development, :test do
  gem 'pg'
  gem 'puma'
  gem 'rspec-rails'
  gem 'rubocop-rails-omakase', require: false
  gem 'webmock'
end
