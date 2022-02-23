# frozen_string_literal: true

Facteur::Engine.routes.draw do
  post 'sendgrid', to: 'webhooks#sendgrid'
end
