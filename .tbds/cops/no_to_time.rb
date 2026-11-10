# frozen_string_literal: true

module RuboCop
  module Cop
    module Tbds
      class NoToTime < Base
        MSG = "`to_time` ignores the app time zone: use `in_time_zone` instead."
        RESTRICT_ON_SEND = %i[to_time].freeze

        def on_send(node)
          add_offense(node)
        end
      end
    end
  end
end
