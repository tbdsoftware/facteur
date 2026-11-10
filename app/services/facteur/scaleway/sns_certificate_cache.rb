# frozen_string_literal: true

module Facteur
  module Scaleway
    # Process-level memo of the SNS signing certificates, keyed by URL
    module SnsCertificateCache
      @certificates = {}
      @mutex = Mutex.new

      def self.fetch(url)
        @mutex.synchronize do
          @certificates[url] ||= yield
        end
      end

      def self.clear
        @mutex.synchronize { @certificates.clear }
      end
    end
  end
end
