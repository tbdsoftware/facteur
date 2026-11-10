# frozen_string_literal: true

module RuboCop
  module Cop
    module Tbds
      class NoRescueStandardError < Base
        MSG = "Don't rescue `StandardError`: rescue the specific exception class you expect."

        def_node_matcher :rescues_standard_error?, <<~PATTERN
          (resbody (array <(const {nil? cbase} :StandardError) ...>) ...)
        PATTERN

        def on_resbody(node)
          add_offense(node) if rescues_standard_error?(node)
        end
      end
    end
  end
end
