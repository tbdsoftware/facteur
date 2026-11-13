# frozen_string_literal: true

source "https://rubygems.org"

gemspec

rails_version = ENV.fetch("RAILS_VERSION", "7.1.3")

gem "oj"
# The CI also runs the suite on Rails 7.2, 8.0 and 8.1, see gemfiles/
gem "rails", "~> #{rails_version}"
gem "sidekiq", "~> #{ENV.fetch('SIDEKIQ_VERSION', '7.2')}"

group :development, :test do
  # json 3 breaks the JSON encoder of ActiveSupport < 8.1 (quirks_mode), and rubocop would pull it
  gem "json", "< 3" if Gem::Version.new(rails_version) < Gem::Version.new("8.1")
  gem "pg"
  gem "puma"
  gem "rspec-rails"
  gem "rubocop-rails-omakase", require: false
  gem "webmock"
end
