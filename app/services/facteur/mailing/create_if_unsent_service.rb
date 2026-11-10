# frozen_string_literal: true

module Facteur
  class Mailing
    class CreateIfUnsentService
      def initialize(attributes)
        @attributes = attributes
      end

      def call
        mailing = ::Facteur::Mailing.new(@attributes)
        mailing.save! if sent_mailings(mailing).empty?

        sent_mailings(mailing).first || mailing
      end

      private

      def sent_mailings(mailing)
        mailings = ::Facteur::Mailing
          .where(resource: mailing.resource, mailer_klass: mailing.mailer_klass, mailer_method: mailing.mailer_method)
          .where("mailer_params @> ?", Oj.dump(mailing.mailer_params))
          .order("created_at ASC")

        if mailing.persisted?
          mailings.where.not(id: mailing.id)
        else
          mailings
        end
      end
    end
  end
end
