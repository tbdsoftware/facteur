# frozen_string_literal: true

require 'net/http'

module Facteur
  module Scaleway
    # Confirms a Scaleway Topics and Events (SNS) subscription by visiting its SubscribeURL
    class ConfirmSubscriptionService
      SUBSCRIBE_HOST_FORMAT = /\Asns\.mnq\.[a-z0-9-]+\.scaleway\.com\z/
      HTTP_TIMEOUT = 5
      HTTP_ERRORS = [
        Timeout::Error, SocketError, SystemCallError, IOError, EOFError, Net::HTTPBadResponse, Net::ProtocolError,
        OpenSSL::SSL::SSLError
      ].freeze
      MANUAL_HINT = 'confirm it manually in the Scaleway console (Topics and Events > Confirm subscription)'

      def initialize(envelope)
        @envelope = envelope
        @url = envelope['SubscribeURL'].to_s
      end

      def call
        uri = subscribe_uri
        if uri.nil?
          Rails.logger.warn("[Facteur] Scaleway SNS SubscribeURL is not trusted, not visited: #{@url}; #{MANUAL_HINT}")
          return false
        end

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                                       open_timeout: HTTP_TIMEOUT, read_timeout: HTTP_TIMEOUT) do |http|
          http.get(uri.request_uri)
        end
        if response.is_a?(Net::HTTPSuccess)
          Rails.logger.info("[Facteur] Scaleway SNS subscription confirmed for #{@envelope['TopicArn']}")
          true
        else
          Rails.logger.warn("[Facteur] Scaleway SNS subscription confirmation answered #{response.code}: #{@url}; " \
                            "#{MANUAL_HINT}")
          false
        end
      rescue *HTTP_ERRORS => e
        Rails.logger.warn("[Facteur] Scaleway SNS subscription confirmation failed (#{e.class} #{e.message}): " \
                          "#{@url}; #{MANUAL_HINT}")
        false
      end

      private

      def subscribe_uri
        uri = URI.parse(@url)
        uri if uri.scheme == 'https' && uri.port == 443 && uri.host.to_s.match?(SUBSCRIBE_HOST_FORMAT)
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
