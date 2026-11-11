# frozen_string_literal: true

module Facteur
  class Mailing
    # mailer_params keep their token until the mailing is finished: a Sidekiq retry rebuilds the mail from them
    class FilterTokensService
      TOKEN_PARAMS = %w[reset_password_token confirmation_token unlock_token invitation_token].freeze
      # Kept identical to the regexp of the filter_tokens_in_facteur_mailings migration template
      TOKEN_FORMAT = /(\A|[^A-Za-z0-9_])(#{TOKEN_PARAMS.join('|')})=[^&"'<># \t\r\n\f\v]+/
      DEVISE_METHODS = %w[
        reset_password_instructions confirmation_instructions unlock_instructions invitation_instructions
      ].freeze
      FILTERED = "[FILTERED]"

      def initialize(mailing)
        @mailing = mailing
      end

      def call
        @mailing.body = @mailing.body.gsub(TOKEN_FORMAT, "\\1\\2=#{FILTERED}") if @mailing.body.present?
        filter_mailer_params if finished?
        @mailing
      end

      private

      def finished?
        @mailing.sent? || @mailing.skipped? || @mailing.error?
      end

      def filter_mailer_params
        params = @mailing.mailer_params
        return if !DEVISE_METHODS.include?(@mailing.mailer_method)
        return if !params.is_a?(Array) || !params.first.is_a?(String)

        @mailing.mailer_params = [FILTERED, *params.drop(1)]
      end
    end
  end
end
