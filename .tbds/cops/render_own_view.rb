# frozen_string_literal: true

module RuboCop
  module Cop
    module Tbds
      class RenderOwnView < Base
        MSG = "Render this controller's own view (implicitly, or `render :show`), " \
              "not another template: share the common JSON in a partial each view renders."
        RESTRICT_ON_SEND = %i[render].freeze

        def_node_matcher :other_template?, <<~PATTERN
          {
            (send nil? :render {str dstr} ...)
            (send nil? :render ... (hash <(pair (sym {:template :file}) _) ...>))
          }
        PATTERN

        def on_send(node)
          add_offense(node) if other_template?(node)
        end
      end
    end
  end
end
