# frozen_string_literal: true

module RuboCop
  module Cop
    module Tbds
      class MigrationStyleDisabledTransactionMultiLine < Base
        MSG = "With `disable_ddl_transaction!`, keep a single statement per `up` / `down` / `change`: " \
              "a failure halfway through leaves the schema half-migrated."
        MIGRATION_METHODS = %i[up down change].freeze

        def_node_search :disables_ddl_transaction?, "(send nil? :disable_ddl_transaction!)"

        def on_class(node)
          return unless node.parent_class&.source&.start_with?("ActiveRecord::Migration")
          return unless disables_ddl_transaction?(node)

          node.each_descendant(:def) do |method|
            next unless MIGRATION_METHODS.include?(method.method_name)
            next unless method.body&.begin_type? && method.body.children.size > 1

            add_offense(method)
          end
        end
      end
    end
  end
end
