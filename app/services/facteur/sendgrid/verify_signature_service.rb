# frozen_string_literal: true

require "base64"
require "openssl"

module Facteur
  module Sendgrid
    class VerifySignatureService
      def initialize(public_key, signature, timestamp, payload)
        @public_key = public_key
        @signature = signature
        @timestamp = timestamp
        @payload = payload
      end

      def call
        if @public_key.blank?
          Rails.logger.error("[Facteur] SendGrid webhook refused: Facteur.sendgrid_webhook_public_key is not configured")
          return false
        end
        return reject("missing signature or timestamp header") if @signature.blank? || @timestamp.blank?

        key = OpenSSL::PKey::EC.new(Base64.decode64(@public_key.to_s))
        signature = Base64.decode64(@signature.to_s)
        key.verify(OpenSSL::Digest::SHA256.new, signature, @timestamp.to_s.b + @payload.to_s.b) || reject("invalid signature")
      rescue OpenSSL::PKey::PKeyError, ArgumentError => error
        reject("signature verification failed: #{error.class} #{error.message}")
      end

      private

      def reject(reason)
        Rails.logger.warn("[Facteur] SendGrid webhook signature rejected: #{reason}")
        false
      end
    end
  end
end
