# frozen_string_literal: true

module RuboCop
  module Cop
    module Tbds
      class NoStrftime < Base
        MSG = "Don't format dates with `strftime`: use `I18n.l` (or `iso8601` in API payloads)."
        RESTRICT_ON_SEND = %i[strftime].freeze

        def on_send(node)
          add_offense(node)
        end
      end
    end
  end
end
