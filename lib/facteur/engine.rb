# frozen_string_literal: true

module Facteur
  class Engine < ::Rails::Engine
    isolate_namespace Facteur

    initializer :facteur do
      if defined?(ActiveAdmin)
        ActiveAdmin.application.load_paths.push root.join('lib', 'facteur', 'admin').to_s
      end
    end
  end
end
