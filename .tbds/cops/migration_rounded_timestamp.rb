# frozen_string_literal: true

module RuboCop
  module Cop
    module Tbds
      class MigrationRoundedTimestamp < Base
        include RangeHelp

        MSG = "Migration timestamp ends with `0000`, so it was probably hand-written: generate it with " \
              "`bin/rails generate migration` so migrations keep their real order across branches."
        ROUNDED_TIMESTAMP = /\A\d{10}0000_/

        def on_new_investigation
          file_path = processed_source.file_path
          return unless file_path && ROUNDED_TIMESTAMP.match?(File.basename(file_path))

          add_offense(source_range(processed_source.buffer, 1, 0))
        end
      end
    end
  end
end
