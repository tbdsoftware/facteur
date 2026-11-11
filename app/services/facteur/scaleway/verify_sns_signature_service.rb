# frozen_string_literal: true

require "base64"
require "net/http"
require "openssl"

module Facteur
  module Scaleway
    class VerifySnsSignatureService
      REGIONS = %w[fr-par nl-ams pl-waw].freeze
      CERT_URL_FORMAT = %r{
        \Ahttps://messaging\.s3\.(?<region>#{REGIONS.join('|')})\.scw\.cloud/\k<region>/sns/sns_certificate_[0-9a-f]+\.pem\z
      }x
      DIGESTS = { "1" => "SHA1", "2" => "SHA256" }.freeze
      NOTIFICATION_KEYS = %w[Message MessageId Subject Timestamp TopicArn Type].freeze
      SUBSCRIPTION_KEYS = %w[Message MessageId SubscribeURL Timestamp Token TopicArn Type].freeze
      OPTIONAL_KEYS = %w[Subject].freeze
      MAX_MESSAGE_AGE = 6.hours
      MAX_CLOCK_SKEW = 5.minutes
      HTTP_TIMEOUT = 5
      FETCH_ERRORS = [
        Timeout::Error, SocketError, SystemCallError, IOError, EOFError, Net::HTTPBadResponse, Net::ProtocolError,
        OpenSSL::SSL::SSLError, OpenSSL::X509::CertificateError
      ].freeze
      MAX_CACHED_CERTIFICATES = 10
      CERTIFICATES = Concurrent::Map.new
      CERTIFICATES_LOCK = Mutex.new

      def initialize(envelope)
        @envelope = envelope
      end

      def call
        digest = DIGESTS[@envelope["SignatureVersion"].to_s]
        return reject("unsupported SignatureVersion #{@envelope['SignatureVersion'].inspect}") if digest.nil?
        return reject("missing Signature") if @envelope["Signature"].blank?

        region = certificate_region
        return reject("untrusted SigningCertURL #{@envelope['SigningCertURL'].inspect}") if region.nil?

        canonical = canonical_string
        return reject("missing signed fields") if canonical.nil?
        return reject("Timestamp #{@envelope['Timestamp'].inspect} is too old, in the future or invalid") if !fresh?

        uri = URI.parse(@envelope["SigningCertURL"])
        certificate = fetch_certificate(uri)
        return reject("certificate unavailable at #{uri}") if certificate.nil?

        expected_name = "sns.mnq.#{region}.scaleway.com"
        name = common_name(certificate)
        return reject("certificate CN #{name.inspect} is not #{expected_name}") if name != expected_name
        return reject("certificate of #{uri} is expired or not yet valid") if !current?(certificate)

        signature = Base64.decode64(@envelope["Signature"].to_s)
        certificate.public_key.verify(OpenSSL::Digest.new(digest), signature, canonical) || reject("invalid signature")
      rescue OpenSSL::PKey::PKeyError => error
        reject("signature verification failed: #{error.message}")
      end

      private

      def certificate_region
        @envelope["SigningCertURL"].to_s.match(CERT_URL_FORMAT)&.[](:region)
      end

      def canonical_string
        keys = @envelope["Type"] == "Notification" ? NOTIFICATION_KEYS : SUBSCRIPTION_KEYS
        keys.each_with_object(+"") do |key, canonical|
          value = @envelope[key]
          next if value.nil? && OPTIONAL_KEYS.include?(key)
          return nil if value.nil?

          canonical << "#{key}\n#{value}\n"
        end
      end

      def fresh?
        timestamp = Time.zone.iso8601(@envelope["Timestamp"].to_s)
        timestamp >= MAX_MESSAGE_AGE.ago && timestamp <= MAX_CLOCK_SKEW.from_now
      rescue ArgumentError
        false
      end

      def common_name(certificate)
        certificate.subject.to_a.find { |name, _value, _type| name == "CN" }&.second
      end

      def current?(certificate)
        Time.current.between?(certificate.not_before, certificate.not_after)
      end

      def fetch_certificate(uri)
        CERTIFICATES[uri.to_s] || download_certificate(uri)&.tap { |certificate| cache_certificate(uri.to_s, certificate) }
      end

      def cache_certificate(url, certificate)
        CERTIFICATES_LOCK.synchronize do
          CERTIFICATES.clear if CERTIFICATES.size >= MAX_CACHED_CERTIFICATES
          CERTIFICATES[url] = certificate
        end
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
      rescue *FETCH_ERRORS => error
        Rails.logger.warn("[Facteur] SNS certificate download failed: #{uri}: #{error.class} #{error.message}")
        nil
      end

      def reject(reason)
        Rails.logger.warn("[Facteur] Scaleway SNS signature rejected: #{reason}")
        false
      end
    end
  end
end
