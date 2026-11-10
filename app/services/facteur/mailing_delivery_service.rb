# frozen_string_literal: true

require "net/smtp"

module Facteur
  class MailingDeliveryService
    def initialize(mailing)
      @mailing = mailing
    end

    def call
      if @mailing.resource.respond_to?(:locale)
        I18n.with_locale(@mailing.resource.locale) do
          deliver
        end
      else
        deliver
      end

      @mailing
    end

    private

    def deliver
      return if @mailing.sent_at || @mailing.skipped_at || @mailing.error_at
      return skip!("expired") if @mailing.created_at < 1.day.ago

      mail =
        if devise_mailer?
          mailer.send(@mailing.mailer_method, @mailing.resource, *@mailing.mailer_params)
        elsif @mailing.mailer_params.is_a?(Hash)
          mailer.with(@mailing.mailer_params.with_indifferent_access).send(@mailing.mailer_method)
        else
          mailer.send(@mailing.mailer_method, *@mailing.mailer_params)
        end
      compute_mail_headers(mail)
      compute_mail_fields(mail)

      return skip!("skipped") if should_skip?
      return skip!("blocked_recipient") if will_be_blocked?

      begin
        mail.deliver_now
      rescue Net::SMTPFatalError, Net::SMTPSyntaxError => error
        return reject!(error)
      end

      @mailing.sent_at ||= Time.current
      @mailing.save!
    end

    def skip!(reason)
      @mailing.skipped_at = Time.current
      @mailing.skip_reason = reason
      @mailing.save!
    end

    def reject!(error)
      @mailing.events = (@mailing.events || []) + [{
        "event" => "dropped",
        "type" => "smtp_rejected",
        "reason" => error.message.strip,
        "provider" => "smtp",
        "timestamp" => Time.current.to_f,
        "provider_event_id" => nil
      }]
      @mailing.save!
    end

    def compute_mail_headers(mail)
      mail.headers("X-Facteur-Mailing-Id" => @mailing.id.to_s)
      mail.headers("X-SMTPAPI" => Oj.dump("unique_args" => { "mn_id" => @mailing.id })) if Facteur.provider.to_s == "sendgrid"
    end

    def compute_mail_fields(mail)
      @mailing.subject ||= mail.subject
      # Mail returns a String instead of an Array for an unparsable address
      @mailing.from ||= Array(mail.from).join(",").presence
      @mailing.to ||= Array(mail.to).join(",").presence
      @mailing.body ||= mail.message.body.presence&.decoded.presence ||
                        mail.body.presence&.parts&.first&.decoded
      @mailing.save!
    end

    def should_skip?
      if mailer.respond_to?(:should_skip_facteur_mailing?)
        mailer.should_skip_facteur_mailing?(@mailing)
      else
        false
      end
    end

    def will_be_blocked?
      return true if @mailing.to.blank?

      !!@mailing.to.match(/@example\.com$/)
    end

    def mailer
      Object.const_get(@mailing.mailer_klass)
    end

    def devise_mailer?
      defined?(::Devise::Mailer) && mailer <= ::Devise::Mailer
    end
  end
end
