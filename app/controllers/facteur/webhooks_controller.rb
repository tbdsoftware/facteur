# frozen_string_literal: true

module Facteur
  # Handles webhooks
  class WebhooksController < ::ApplicationController
    layout false
    skip_before_action :verify_authenticity_token
    before_action :set_default_request_format

    def set_default_request_format
      request.format = :json unless params[:format]
    end

    def sendgrid
      json_params = ActiveSupport::JSON.decode(request.body.read)
      MailProviderHookWorker.perform_async(:sendgrid, json_params)

      head 200
    end
  end
end
