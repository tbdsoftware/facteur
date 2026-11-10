# frozen_string_literal: true

require "active_support/core_ext/module/attribute_accessors"

module Facteur
  mattr_accessor :provider, default: :sendgrid
  mattr_accessor :scaleway_webhook_token, default: nil

  def self.configure
    yield self
  end
end
