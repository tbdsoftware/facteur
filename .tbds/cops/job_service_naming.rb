# frozen_string_literal: true

module RuboCop
  module Cop
    module Tbds
      class JobServiceNaming < Base
        MSG = "A job only delegates to its namesake service: expected `%<expected>s.new(...).call`, " \
              "found `%<actual>s`."

        def_node_matcher :service_call, <<~PATTERN
          {
            (send (send $const :new ...) :call ...)
            (send $const :call ...)
          }
        PATTERN

        def on_class(node)
          job_name = full_name(node)
          return unless job_name.end_with?("Job")

          expected = job_name.delete_suffix("Job") + "Service"
          node.each_descendant(:send) do |send_node|
            service = service_call(send_node)
            next unless service
            next if same_constant?(expected, service.const_name)

            add_offense(send_node, message: format(MSG, expected: expected, actual: service.const_name))
          end
        end

        private

        def full_name(class_node)
          namespaces = class_node.each_ancestor(:module, :class).map { |ancestor| ancestor.identifier.const_name }
          [*namespaces.reverse, class_node.identifier.const_name].join("::")
        end

        def same_constant?(expected, actual)
          actual = actual.delete_prefix("::")
          expected == actual || expected.end_with?("::#{actual}")
        end
      end
    end
  end
end
