# frozen_string_literal: true

require 'rails/generators/active_record'

module Facteur
  module Generators
    class ActiveRecordGenerator < Rails::Generators::Base
      include ActiveRecord::Generators::Migration
      source_root File.join(__dir__, 'templates')

      MIGRATIONS = {
        'active_record_migration.rb' => 'create_facteur_mailings',
        'add_tracking_to_facteur_mailings.rb' => 'add_tracking_to_facteur_mailings'
      }.freeze

      def copy_templates
        MIGRATIONS.each do |template, name|
          if self.class.migration_exists?(File.join(destination_root, 'db', 'migrate'), name)
            say_status :skip, "db/migrate/*_#{name}.rb already exists", :yellow
          else
            migration_template template, "db/migrate/#{name}.rb", migration_version: migration_version
          end
        end
      end

      def migration_version
        "[#{ActiveRecord::VERSION::MAJOR}.#{ActiveRecord::VERSION::MINOR}]"
      end
    end
  end
end
