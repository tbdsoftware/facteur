# frozen_string_literal: true

module Facteur
  # Handles webhooks
  class WebhooksController < ::ApplicationController
    layout false
    skip_before_action :verify_authenticity_token

    def sendgrid
      json_params = request.body.read.presence && ActiveSupport::JSON.decode(request.body.read)
      MailProviderHookWorker.perform_async(:sendgrid, json_params)

      head 200
    end
  end
end
