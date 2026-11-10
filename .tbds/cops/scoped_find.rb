# frozen_string_literal: true

module RuboCop
  module Cop
    module Tbds
      class ScopedFind < Base
        MSG = "Look `%<model>s` up through its already-scoped parent association " \
              "(e.g. `current_promoter.programs.friendly.find(...)`), not on the bare class."
        RESTRICT_ON_SEND = %i[find].freeze

        def_node_matcher :bare_find_receiver, <<~PATTERN
          (send {$const (send $const :friendly)} :find ...)
        PATTERN

        def on_send(node)
          const = bare_find_receiver(node)
          return unless const
          return if allowed_constants.include?(const.const_name)

          add_offense(node, message: format(MSG, model: const.const_name))
        end

        private

        def allowed_constants
          Array(cop_config["AllowedConstants"]).map(&:to_s)
        end
      end
    end
  end
end
