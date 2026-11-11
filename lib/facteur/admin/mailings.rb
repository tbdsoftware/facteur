# frozen_string_literal: true

if defined?(ActiveAdmin)
  status_i18n_key = ->(status) { "activerecord.attributes.#{::Facteur::Mailing.model_name.i18n_key}.statuses.#{status}" }

  status_label = lambda do |status|
    return if status.nil?

    ::I18n.t(status_i18n_key.call(status), default: [:"attributes.statuses.#{status}", status.to_s])
  end

  status_color = lambda do |status|
    case status.to_sym
    when :current_status_pending
      :orange
    when :current_status_sent, :current_status_processed
      :black
    when :current_status_delivered
      :gray
    when :current_status_opened, :current_status_clicked
      :green
    when :current_status_skipped
      :yellow
    when :current_status_error
      :red
    end
  end

  status_filter_collection = lambda do
    ::Facteur::Mailing.statuses.map do |status, value|
      [::I18n.t(status_i18n_key.call(status), default: status.humanize), value]
    end
  end

  ActiveAdmin.register ::Facteur::Mailing do
    menu parent: "Admin"
    actions :all, except: %i[new create edit update]

    filter :status, as: :select, collection: status_filter_collection
    filter :skip_reason, as: :select, collection: -> { ::Facteur::Mailing::SKIP_REASONS }
    filter :mailer_method
    filter :sent_at
    filter :created_at

    index do
      selectable_column
      id_column
      column :status do |mailing|
        status_tag status_label.call(mailing.status), class: status_color.call(mailing.status)
      end
      column :skip_reason
      column :mailer_klass
      column :mailer_method
      column :to
      column :events do |mailing|
        mailing.events&.count
      end
      column :created_at
      actions
    end

    show do
      columns do
        column do
          attributes_table title: "Attributs" do
            row :status do |mailing|
              status_tag status_label.call(mailing.status), class: status_color.call(mailing.status)
            end
            row :resource
            row :mailer_klass
            row :mailer_method
            row :mailer_params
            row :provider_message_ids
          end

          attributes_table title: "Dates" do
            row :sent_at
            row :processed_at
            row :delivered_at
            row :opened_at
            row :clicked_at
            row :skipped_at
            row :created_at
            row :updated_at
          end

          attributes_table title: "Error" do
            row :error_msg
            row :error_at
          end

          attributes_table title: "Skip" do
            row :skip_reason
            row :skipped_at
          end
        end

        column do
          panel "Contenu" do
            attributes_table_for resource do
              row :to
              row :from
              row :subject
            end
            # Scripts of a stored body must never run in the admin's origin. Arbre 1 drops empty attribute values,
            # and a blank sandbox token list keeps every restriction
            iframe sandbox: " ", style: "width: 100%; height: 400px; border: none; margin-top: 14px;",
                   src: html_body_admin_facteur_mailing_path(resource)
          end

          panel "Events" do
            pre do
              resource.events.to_yaml
            end
          end
        end
      end
    end

    member_action :html_body do
      response.headers["Content-Security-Policy"] = "sandbox"
      render html: resource.body.to_s.html_safe
    end
  end
end
