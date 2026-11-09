# frozen_string_literal: true

if Rails.env.development? && ENV['FACTEUR_INLINE_JOBS'] == '1'
  require 'sidekiq/testing'
  Sidekiq::Testing.inline!
end
