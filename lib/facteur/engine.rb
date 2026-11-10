# frozen_string_literal: true

module Facteur
  class Engine < ::Rails::Engine
    isolate_namespace Facteur

    initializer :facteur do
      if defined?(ActiveAdmin)
        ActiveAdmin.application.load_paths.push root.join("lib", "facteur", "admin").to_s
      end
    end

    # After the host's own initializers, which may assign filter_parameters instead of appending to it
    initializer "facteur.filter_parameters", after: :load_config_initializers do |app|
      app.config.filter_parameters << :facteur_token if !app.config.filter_parameters.include?(:facteur_token)
    end
  end
end
