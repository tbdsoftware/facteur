# frozen_string_literal: true

module Facteur
  # This will probably one day be extracted into a gem
  # This is some common behavior not specific to Facteur
  module ApplicationRecordable
    extend ActiveSupport::Concern

    def human_enum_name(enum_name)
      self.class.human_enum_name(enum_name, send(enum_name))
    end

    def defined_enum?(attr)
      self.class.defined_enum?(attr)
    end

    class_methods do
      def human_enum_name(enum_name, enum_value)
        return if enum_value.nil?

        localized_enum_value(enum_name, enum_value)
      end

      def t_attr(attr_nam)
        i18n_key = [
          'activerecord',
          'attributes',
          model_name.i18n_key,
          attr_nam.to_s
        ].join('.')
        default_i18n_key = ['attributes', attr_nam.to_s].join('.').to_sym

        ::I18n.t(i18n_key, default: [default_i18n_key, attr_nam.to_s])
      end

      def enum_i18n_key(enum_name, enum_value)
        [
          'activerecord',
          'attributes',
          model_name.i18n_key,
          enum_name.to_s.pluralize,
          enum_value
        ].join('.')
      end

      def localized_enum_value(enum_name, enum_value)
        i18n_key = [
          'activerecord',
          'attributes',
          model_name.i18n_key,
          enum_name.to_s.pluralize,
          enum_value
        ].join('.')
        default_i18n_key = [
          'attributes',
          enum_name.to_s.pluralize,
          enum_value
        ].join('.').to_sym

        ::I18n.t(i18n_key, default: [default_i18n_key, enum_value.to_s])
      end

      # Inspired by formtastic/lib/formtastic/inputs/base/collections.rb
      def collection_from_enum(method)
        return unless defined_enum?(method)

        method_name = method.to_s

        enum_options_hash = defined_enums[method_name]
        enum_options_hash.map do |name, _value|
          label = ::I18n.translate(enum_i18n_key(method_name, name),
                                   default: name.humanize)
          [label, name]
        end
      end

      def collection_from_enum_with_ivalues(method)
        return unless defined_enum?(method)

        method_name = method.to_s

        enum_options_hash = defined_enums[method_name]
        enum_options_hash.map do |name, value|
          label = ::I18n.translate(enum_i18n_key(method_name, name),
                                   default: name.humanize)
          [label, value]
        end
      end

      def defined_enum?(attr)
        respond_to?(:defined_enums) && defined_enums.key?(attr.to_s)
      end
    end
  end
end
