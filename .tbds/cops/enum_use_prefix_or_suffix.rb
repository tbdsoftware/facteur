# frozen_string_literal: true

module RuboCop
  module Cop
    module Tbds
      class EnumUsePrefixOrSuffix < Base
        MSG = "Give the enum a `prefix:` or `suffix:` so its generated methods and scopes can't clash."

        def_node_matcher :enum_options, <<~PATTERN
          (send nil? :enum (sym _) hash $...)
        PATTERN

        def on_send(node)
          options = enum_options(node)
          return unless options
          return if options.any? { |option| prefixed_or_suffixed?(option) }

          add_offense(node)
        end

        private

        def prefixed_or_suffixed?(option)
          option.hash_type? && option.pairs.any? do |pair|
            pair.key.sym_type? && %i[prefix suffix].include?(pair.key.value) && !pair.value.false_type?
          end
        end
      end
    end
  end
end
