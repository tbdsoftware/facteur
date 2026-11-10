# frozen_string_literal: true

module RuboCop
  module Cop
    module Tbds
      class UpdateAllTouchesUpdatedAt < Base
        MSG = "`%<method>s` skips callbacks and doesn't touch `updated_at`: set it explicitly " \
              "(e.g. `updated_at: Time.current`)."
        MSG_SINGLE_COLUMN = "`update_column` skips callbacks and doesn't touch `updated_at`: use " \
                            "`update_columns` and set `updated_at` (e.g. `updated_at: Time.current`)."
        RESTRICT_ON_SEND = %i[update_all update_columns update_column].freeze
        TIMESTAMP_COLUMNS = %w[updated_at updated_on].freeze

        def on_send(node)
          argument = node.first_argument
          return if argument.nil?

          if node.method?(:update_column)
            check_single_column(node, argument)
          else
            check_bulk(node, argument)
          end
        end

        private

        def check_bulk(node, argument)
          return unless argument.type?(:hash, :str, :dstr, :array)
          return if sets_updated_at?(argument)

          add_offense(node, message: format(MSG, method: node.method_name))
        end

        def check_single_column(node, argument)
          return unless argument.type?(:sym, :str)
          return if TIMESTAMP_COLUMNS.include?(argument.value.to_s)

          add_offense(node, message: MSG_SINGLE_COLUMN)
        end

        def sets_updated_at?(argument)
          return TIMESTAMP_COLUMNS.any? { |column| argument.source.include?(column) } unless argument.hash_type?

          argument.pairs.any? do |pair|
            pair.key.type?(:sym, :str) && TIMESTAMP_COLUMNS.include?(pair.key.value.to_s)
          end
        end
      end
    end
  end
end
