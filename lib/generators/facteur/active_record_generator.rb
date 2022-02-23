# frozen_string_literal: true

require 'rails/generators/active_record'

module Facteur
  module Generators
    class ActiveRecordGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration
      source_root File.join(__dir__, 'templates')

      def copy_templates
        migration_template 'active_record_migration.rb', 'db/migrate/create_facteur_mailings.rb', migration_version: migration_version
      end

      def migration_version
        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end
    end
  end
end
