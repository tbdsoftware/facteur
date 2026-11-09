# frozen_string_literal: true

Rails.application.routes.draw do
  mount Facteur::Engine => '/facteur'
end
