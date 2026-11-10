# frozen_string_literal: true

module RuboCop
  module Cop
    module Tbds
      class NoJsonbPathOperator < Base
        MSG = "Avoid the `#>` / `#>>` JSONB operators: they don't match expression indexes built with " \
              "`->` / `->>`, so queries fall back to sequential scans. Use `col -> 'a' ->> 'b'` instead."

        def on_str(node)
          add_offense(node) if node.value.match?(/#>>?\s*'/)
        end
      end
    end
  end
end
