# frozen_string_literal: true

module Facteur
  # This class represents mail that we have sent. This is used to track which mail we send to whom,
  # and ensure that we do not send an email twice
  class Mailing < ActiveRecord::Base
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

    def to_s
      "Facteur::Mailing ##{id}"
    end

    def sorted_events
      (events || [])
        .map { |e| e.merge('datetime' => Time.zone.at(e['timestamp'].to_f.to_r.round(6)).to_datetime) }
        .each_with_index
        .sort_by { |e, i| [e['timestamp'].to_f, i] }
        .map(&:first)
    end

    private

    def schedule_delivery
      ::Facteur::MailingDeliveryJob.perform_async(id)
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
