# frozen_string_literal: true

require 'net/smtp'

module Facteur
  # This class represents mail that we have sent. This is used to track which mail we send to whom,
  # and ensure that we do not send an email twice
  class Mailing < ActiveRecord::Base
    include ::Facteur::ApplicationRecordable

    # 'suppressed' is reserved for a future suppression list and is not set yet
    SKIP_REASONS = %w[expired skipped blocked_recipient suppressed].freeze
    ERROR_EVENTS = %w[dropped bounce spamreport].freeze
    # Scaleway emits this generic terminal event alongside the specific one (e.g. email_mailbox_not_found)
    GENERIC_DROP_TYPE = 'email_dropped'

    belongs_to :resource, polymorphic: true, optional: true

    validates :skip_reason, inclusion: { in: SKIP_REASONS }, allow_nil: true

    before_save :compute_events
    before_save :compute_status
    after_commit :schedule_delivery, on: :create

    enum :status, {
      current_status_pending: 0,
      current_status_sent: 1,
      current_status_processed: 2,
      current_status_delivered: 3,
      current_status_opened: 4,
      current_status_clicked: 5,
      current_status_skipped: 98,
      current_status_error: 99
    }

    # Define methods for all our possible date stuff value
    %i[pending sent processed delivered opened clicked skipped error].each do |method|
      scope method, -> { where.not("#{method}_at" => nil) }
      scope "not_#{method}".to_sym, -> { where("#{method}_at" => nil) }

      define_method "#{method}?".to_sym do
        send("#{method}_at").present?
      end
    end

    def self.create_if_unsent!(params)
      mn = new(params)
      mn.save! if mn.sent_mailings.empty?

      mn.sent_mailings.first || mn
    end

    def to_s
      "Facteur::Mailing ##{id}"
    end

    def will_be_blocked?
      return true if to.blank?

      !!to.match(/@example\.com$/)
    end

    def sent_mailings
      mns =
        ::Facteur::Mailing
        .where(resource: resource,
               mailer_klass: mailer_klass,
               mailer_method: mailer_method)
        .where('mailer_params @> ?', Oj.dump(mailer_params))
        .order('created_at ASC')

      if persisted?
        mns.where.not(id: id)
      else
        mns
      end
    end

    def mailer
      Object.const_get(mailer_klass)
    end

    def compute_mail
      if devise_mailer?
        mailer.send(mailer_method, resource, *mailer_params)
      else
        mailer.send(mailer_method, *mailer_params)
      end
    end

    # Method to override in the app world in order to skip some kind of messages
    def should_skip?
      if mailer.respond_to?(:should_skip_facteur_mailing?)
        mailer.should_skip_facteur_mailing?(self)
      else
        false
      end
    end

    def deliver
      if resource.respond_to?(:locale)
        I18n.with_locale(resource.locale) do
          inner_deliver
        end
      else
        inner_deliver
      end
    end

    def inner_deliver
      return if sent_at || skipped_at || error_at
      return skip!('expired') if created_at < 1.day.ago

      mail = if devise_mailer?
               mailer.send(mailer_method, resource, *mailer_params)
             elsif mailer_params.is_a?(Hash)
               # This is new parameterize method
               mailer.with(mailer_params.with_indifferent_access).send(mailer_method)
             else
               mailer.send(mailer_method, *mailer_params)
             end
      compute_mail_headers(mail)
      compute_mail_fields(mail)

      return skip!('skipped') if should_skip?
      return skip!('blocked_recipient') if will_be_blocked?

      begin
        mail.deliver_now
      rescue Net::SMTPFatalError, Net::SMTPSyntaxError => e
        return reject!(e)
      end

      self.sent_at ||= DateTime.current
      save!
    end

    def skip!(reason)
      self.skipped_at = Time.current
      self.skip_reason = reason
      save!
    end

    def compute_mail_headers(mail)
      mail.headers('X-Facteur-Mailing-Id' => id.to_s)
      mail.headers('X-SMTPAPI' => Oj.dump('unique_args' => { 'mn_id' => id })) if Facteur.provider.to_s == 'sendgrid'
    end

    def prospect_demo_user?
      return true if resource.is_a?(Prospect) && resource.demo_user?
      return resource.prospect.demo_user? if resource.respond_to?(:prospect)

      false
    end

    def compute_mail_fields(mail)
      self.subject ||= mail.subject
      # Mail returns a String instead of an Array for an unparsable address
      self.from ||= Array(mail.from).join(',').presence
      self.to ||= Array(mail.to).join(',').presence
      self.body ||= mail.message.body.presence&.decoded.presence ||
                    mail.body.presence&.parts&.first&.decoded
      save!
    end

    def sorted_events
      (events || [])
        .map { |e| e.merge('datetime' => Time.zone.at(e['timestamp'].to_f.to_r.round(6)).to_datetime) }
        .each_with_index
        .sort_by { |e, i| [e['timestamp'].to_f, i] }
        .map(&:first)
    end

    def status_class
      case status.to_sym
      when :current_status_pending
        :orange
      when :current_status_sent, :current_status_processed
        :black
      when :current_status_delivered
        :gray
      when :current_status_opened, :current_status_clicked
        :green
      when :current_status_skipped
        :yellow
      when :current_status_error
        :red
      end
    end

    protected

    def schedule_delivery
      ::Facteur::MailingDeliveryJob.perform_async(id)
    end

    def devise_mailer?
      defined?(::Devise::Mailer) && mailer <= ::Devise::Mailer
    end

    def reject!(error)
      self.events = (events || []) + [{
        'event' => 'dropped',
        'type' => 'smtp_rejected',
        'reason' => error.message.strip,
        'provider' => 'smtp',
        'timestamp' => Time.current.to_f,
        'provider_event_id' => nil
      }]
      save!
    end

    def compute_events
      return unless events_changed?
      return if events.blank?

      self.error_msg = nil
      ordered_events = sorted_events
      specific_error = ordered_events.any? { |e| error_event?(e) && e['type'] != GENERIC_DROP_TYPE }
      ordered_events.each do |event|
        case event['event'].to_s.downcase
        when 'processed'
          self.processed_at ||= event['datetime']
        when 'delivered'
          self.delivered_at ||= event['datetime']
        when 'open'
          self.opened_at ||= event['datetime']
        when 'click'
          self.clicked_at ||= event['datetime']
        when *ERROR_EVENTS
          self.error_msg = error_msg_for_event(event) if !specific_error || event['type'] != GENERIC_DROP_TYPE
          self.error_at = [error_at, event['datetime']].compact.min
        end
      end
    end

    def error_event?(event)
      ERROR_EVENTS.include?(event['event'].to_s.downcase)
    end

    def error_msg_for_event(event)
      new_msg = case event['event'].downcase
                when 'bounce', 'dropped'
                  "#{event['type'] || event['event'].downcase}: #{event['reason']}"
                else
                  event['event'].downcase
                end

      messages = (error_msg || '').split('; ')
      return error_msg if messages.include?(new_msg)

      messages.push(new_msg).join('; ')
    end

    def compute_status
      self.status = if error_at.present?
                      :current_status_error
                    elsif skipped_at.present?
                      :current_status_skipped
                    elsif clicked_at.present?
                      :current_status_clicked
                    elsif opened_at.present?
                      :current_status_opened
                    elsif delivered_at.present?
                      :current_status_delivered
                    elsif processed_at.present?
                      :current_status_processed
                    elsif sent_at.present?
                      :current_status_sent
                    else
                      :current_status_pending
                    end
    end
  end
end
