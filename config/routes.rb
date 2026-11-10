# frozen_string_literal: true

Facteur::Engine.routes.draw do
  post "sendgrid", to: "webhooks#sendgrid" if Facteur.enabled_webhooks.include?(:sendgrid)
  post "scaleway", to: "webhooks#scaleway" if Facteur.enabled_webhooks.include?(:scaleway)
end
