# frozen_string_literal: true

require "active_support/core_ext/module/attribute_accessors"

module Facteur
  mattr_accessor :provider, default: :sendgrid
  mattr_accessor :webhooks, default: nil
  mattr_accessor :sendgrid_webhook_public_key, default: nil
  mattr_accessor :scaleway_webhook_token, default: nil
  mattr_accessor :scaleway_topic_arns, default: []
  mattr_accessor :store_body, default: true

  def self.configure
    yield self
  end

  def self.enabled_webhooks
    Array(webhooks || provider).map(&:to_sym)
  end
end
