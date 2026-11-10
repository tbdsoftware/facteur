# frozen_string_literal: true

module RuboCop
  module Cop
    module Tbds
      class MailerMethodsArguments < Base
        MSG = "Pass arguments to %<mailer>s through `with`: `%<suggestion>s`."

        def_node_matcher :mailer_call_with_arguments, <<~PATTERN
          (send $(const _ _) $_ $_ ...)
        PATTERN

        def on_send(node)
          mailer, method, = mailer_call_with_arguments(node)
          return unless mailer&.short_name.to_s.end_with?("Mailer") && method.to_s.end_with?("_email")

          params = node.arguments.each_with_index.map { |argument, index| "param_#{index + 1}: #{argument.source}" }
          suggestion = "#{mailer.source}.with(#{params.join(', ')}).#{method}"
          add_offense(node, message: format(MSG, mailer: mailer.source, suggestion: suggestion))
        end
      end
    end
  end
end
