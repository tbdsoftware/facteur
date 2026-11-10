# frozen_string_literal: true

module RuboCop
  module Cop
    module Tbds
      class EnumValueAsString < Base
        MSG = "Enum values must be strings (`{ active: \"active\" }`), not integers."

        def_node_matcher :enum_values, <<~PATTERN
          (send nil? :enum (sym _) $hash ...)
        PATTERN

        def on_send(node)
          values = enum_values(node)
          return unless values
          return if values.pairs.all? { |pair| pair.value.str_type? || pair.value.sym_type? }

          add_offense(node)
        end
      end
    end
  end
end
