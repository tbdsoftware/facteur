# frozen_string_literal: true

require 'base64'
require 'net/http'
require 'openssl'

module Facteur
  module Scaleway
    # Verifies the signature of a Scaleway Topics and Events (SNS) message
    class VerifySnsSignatureService
      CERT_HOST_FORMAT = /\Amessaging\.s3\.[a-z0-9-]+\.scw\.cloud\z/
      DIGESTS = { '1' => 'SHA1', '2' => 'SHA256' }.freeze
      NOTIFICATION_KEYS = %w[Message MessageId Subject Timestamp TopicArn Type].freeze
      SUBSCRIPTION_KEYS = %w[Message MessageId SubscribeURL Timestamp Token TopicArn Type].freeze
      OPTIONAL_KEYS = %w[Subject].freeze
      HTTP_TIMEOUT = 5
      FETCH_ERRORS = [
        Timeout::Error, SocketError, SystemCallError, IOError, EOFError, Net::HTTPBadResponse, Net::ProtocolError,
        OpenSSL::SSL::SSLError, OpenSSL::X509::CertificateError
      ].freeze
      CERTIFICATES = Concurrent::Map.new

      def initialize(envelope)
        @envelope = envelope
      end

      def call
        digest = DIGESTS[@envelope['SignatureVersion'].to_s]
        return reject("unsupported SignatureVersion #{@envelope['SignatureVersion'].inspect}") if digest.nil?
        return reject('missing Signature') if @envelope['Signature'].blank?

        uri = certificate_uri
        return reject("untrusted SigningCertURL #{@envelope['SigningCertURL'].inspect}") if uri.nil?

        canonical = canonical_string
        return reject('missing signed fields') if canonical.nil?

        certificate = fetch_certificate(uri)
        return reject("certificate unavailable at #{uri}") if certificate.nil?

        signature = Base64.decode64(@envelope['Signature'].to_s)
        certificate.public_key.verify(OpenSSL::Digest.new(digest), signature, canonical) || reject('invalid signature')
      rescue OpenSSL::PKey::PKeyError => e
        reject("signature verification failed: #{e.message}")
      end

      private

      def certificate_uri
        uri = URI.parse(@envelope['SigningCertURL'].to_s)
        uri if uri.scheme == 'https' && uri.port == 443 && uri.host.to_s.match?(CERT_HOST_FORMAT)
      rescue URI::InvalidURIError
        nil
      end

      def canonical_string
        keys = @envelope['Type'] == 'Notification' ? NOTIFICATION_KEYS : SUBSCRIPTION_KEYS
        keys.each_with_object(+'') do |key, canonical|
          value = @envelope[key]
          next if value.nil? && OPTIONAL_KEYS.include?(key)
          return nil if value.nil?

          canonical << "#{key}\n#{value}\n"
        end
      end

      def fetch_certificate(uri)
        CERTIFICATES[uri.to_s] || download_certificate(uri)&.tap { |certificate| CERTIFICATES[uri.to_s] = certificate }
      end

      def download_certificate(uri)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true,
                                                       open_timeout: HTTP_TIMEOUT, read_timeout: HTTP_TIMEOUT) do |http|
          http.get(uri.request_uri)
        end
        if response.is_a?(Net::HTTPSuccess)
          Rails.logger.info("[Facteur] SNS certificate downloaded from #{uri}")
          OpenSSL::X509::Certificate.new(response.body)
        else
          Rails.logger.warn("[Facteur] SNS certificate download failed: #{uri} answered #{response.code}")
          nil
        end
      rescue *FETCH_ERRORS => e
        Rails.logger.warn("[Facteur] SNS certificate download failed: #{uri}: #{e.class} #{e.message}")
        nil
      end

      def reject(reason)
        Rails.logger.warn("[Facteur] Scaleway SNS signature rejected: #{reason}")
        false
      end
    end
  end
end
