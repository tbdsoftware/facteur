# frozen_string_literal: true

module RuboCop
  module Cop
    module Tbds
      class MigrationDatetimeColumnNaming < Base
        MSG_AT = "datetime columns must have names ending in `_at`."
        MSG_ON = "date columns must have names ending in `_on`."
        DATETIME_TYPES = %i[datetime timestamp timestamptz].freeze
        RESTRICT_ON_SEND = [:add_column, :change_column, :column, :date, *DATETIME_TYPES].freeze

        def on_send(node)
          name, type = column_name_and_type(node)
          return unless name && type

          if DATETIME_TYPES.include?(type.to_sym) && !name.to_s.end_with?("_at")
            add_offense(node, message: MSG_AT)
          elsif type.to_sym == :date && !name.to_s.end_with?("_on")
            add_offense(node, message: MSG_ON)
          end
        end

        private

        def column_name_and_type(node)
          case node.method_name
          when :add_column, :change_column then [literal(node.arguments[1]), literal(node.arguments[2])]
          when :column then [literal(node.arguments[0]), literal(node.arguments[1])]
          else [literal(node.arguments[0]), node.method_name]
          end
        end

        def literal(node)
          node.value if node&.type?(:sym, :str)
        end
      end
    end
  end
end
