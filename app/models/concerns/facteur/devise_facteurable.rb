# frozen_string_literal: true

module Facteur
  # When included on a devise model, this concern makes devise send emails via our Mailing model
  module DeviseFacteurable
    extend ActiveSupport::Concern

    protected

    def send_devise_notification(notification, *args)
      Mailing.create!(resource: self,
                      mailer_klass: devise_mailer,
                      mailer_method: notification,
                      mailer_params: args)
    end
  end
end
