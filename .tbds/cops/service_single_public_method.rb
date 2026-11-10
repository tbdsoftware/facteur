# frozen_string_literal: true

module RuboCop
  module Cop
    module Tbds
      class ServiceSinglePublicMethod < Base
        MSG = "A service exposes a single public `#call` (invoked as `.new(...).call`): " \
              "make `%<name>s` private or move it to its own service."
        CLASS_METHOD_MSG = "A service has no class methods: define `#call` as an instance method, " \
                           "invoked as `.new(...).call`, instead of `%<name>s`."
        ALLOWED_INSTANCE_METHODS = %i[call initialize].freeze
        VISIBILITY_METHODS = %i[public private protected].freeze

        def on_class(node)
          return unless node.identifier.short_name.to_s.end_with?("Service")

          visibility = :public
          body_children(node).each do |child|
            if visibility_change?(child)
              visibility = child.method_name
            elsif child.def_type?
              check_instance_method(child) if visibility == :public
            elsif child.defs_type?
              add_offense(child, message: format(CLASS_METHOD_MSG, name: "self.#{child.method_name}"))
            elsif child.sclass_type?
              add_offense(child, message: format(CLASS_METHOD_MSG, name: "class << self"))
            end
          end
        end

        private

        def body_children(node)
          return [] unless node.body

          node.body.begin_type? ? node.body.children : [node.body]
        end

        def visibility_change?(node)
          node.send_type? && node.receiver.nil? && node.arguments.empty? &&
            VISIBILITY_METHODS.include?(node.method_name)
        end

        def check_instance_method(node)
          return if ALLOWED_INSTANCE_METHODS.include?(node.method_name)

          add_offense(node, message: format(MSG, name: "##{node.method_name}"))
        end
      end
    end
  end
end
