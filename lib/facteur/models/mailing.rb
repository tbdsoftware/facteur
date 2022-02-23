# frozen_string_literal: true

module Facteur
  # This class represents mail that we have sent. This is used to track which mail we send to whom,
  # and ensure that we do not send an email twice
  class Mailing < ActiveRecord::Base
    belongs_to :resource, polymorphic: true, optional: true

    before_save :compute_events
    before_save :compute_status
    after_commit :schedule_delivery, on: :create

    enum status: {
      current_status_pending: 0,
      current_status_sent: 1,
      current_status_processed: 2,
      current_status_delivered: 3,
      current_status_opened: 4,
      current_status_clicked: 5,
      current_status_error: 99
    }

    # Define methods for all our possible date stuff value
    %i[pending sent processed delivered opened clicked error].each do |method|
      scope method, -> { where.not("#{method}_at" => nil) }
      scope "not_#{method}".to_sym, -> { where("#{method}_at" => nil) }

      define_method "#{method}?".to_sym do
        send("#{method}_at").present?
      end
    end

    def self.create_if_unsent!(params)
      mn = MailNotification.new(params)
      mn.save! if mn.sent_mail_notifications.empty?

      mn.sent_mail_notifications.first || mn
    end

    def to_s
      "MailNotification ##{id}"
    end

    def will_be_blocked?
      return true if to.blank?

      !!to.match(/@example\.com$/)
    end

    def sent_mail_notifications
      mns =
        MailNotification
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

    def deliver
      return if sent_at
      return if created_at < 1.day.ago

      mail = mailer.send(mailer_method, *mailer_params)
      if Rails.env.production?
        mail.headers('X-SMTPAPI' => Oj.dump('unique_args' => { 'mn_id' => id }))
      end
      compute_mail_fields(mail)

      return if will_be_blocked?
      # Do not deliver for demo user tests
      return if mailer == PromoterMailer && prospect_demo_user?

      mail.deliver_now
      self.sent_at ||= DateTime.current
      save!
    end

    def prospect_demo_user?
      return true if resource.is_a?(Prospect) && resource.demo_user?
      return resource.prospect.demo_user? if resource.respond_to?(:prospect)

      false
    end

    def compute_mail_fields(mail)
      self.subject ||= mail.subject
      self.from ||= mail.from.join(',')
      self.to ||= mail.to.join(',')
      self.body ||= mail.message.body.decoded.presence || mail.body.parts.first&.decoded
      save!
    end

    def sorted_events
      events
        .each.with_index { |e, i| events[i]['datetime'] = Time.zone.at(e['timestamp']).to_datetime }
        .sort { |ea, eb| ea['timestamp'] <=> eb['timestamp'] }
    end

    def status_class
      case object.status.to_sym
      when :current_status_pending
        :orange
      when :current_status_sent, :current_status_processed
        :black
      when :current_status_delivered
        :gray
      when :current_status_opened, :current_status_clicked
        :green
      when :current_status_error
        :red
      end
    end

    protected

    def schedule_delivery
      MailNotificationDeliveryWorker.perform_async(id)
    end

    def compute_events
      return unless events_changed?
      return if events.blank?

      self.error_msg = nil
      sorted_events.each do |event|
        case event['event'].downcase
        when 'processed'
          self.processed_at ||= event['datetime']
        when 'delivered'
          self.delivered_at ||= event['datetime']
        when 'open'
          self.opened_at ||= event['datetime']
        when 'click'
          self.clicked_at ||= event['datetime']
        when 'dropped', 'bounce', 'spamreport'
          self.error_msg = error_msg_for_event(event)
          self.error_at ||= event['datetime']
        end
      end
    end

    def error_msg_for_event(event)
      new_msg = case event['event'].downcase
                when 'bounce', 'dropped'
                  "#{event['type'] || event['event'].downcase}: #{event['reason']}"
                else
                  event['event'].downcase
                end

      (error_msg || '').split('; ').push(new_msg).join('; ')
    end

    def compute_status
      self.status = if error_at.present?
                      :current_status_error
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
