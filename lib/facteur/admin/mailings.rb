# frozen_string_literal: true

return
ActiveAdmin.register Facteur::Mailing do
  menu parent: 'Admin'
  actions :all, except: %i[new create edit update]

  filter :mailer_method
  filter :sent_at
  filter :created_at

  index do
    selectable_column
    id_column
    column :status do |mn|
      status_tag mn.human_enum_name(:status), class: mn.status_class
    end
    column :mailer_klass
    column :mailer_method
    column :to
    column :events do |mn|
      mn.events&.count
    end
    column :created_at
    actions
  end

  show do
    columns do
      column do
        attributes_table title: 'Attributs' do
          row :status do |mn|
            status_tag mn.human_enum_name(:status), class: mn.status_class
          end
          row :resource
          row :mailer_klass
          row :mailer_method
          row :mailer_params
        end

        attributes_table title: 'Dates' do
          row :sent_at
          row :processed_at
          row :delivered_at
          row :opened_at
          row :clicked_at
          row :created_at
          row :updated_at
        end

        attributes_table title: 'Error' do
          row :error_msg
          row :error_at
        end
      end

      column do
        panel 'Contenu' do
          attributes_table_for mail_notification do
            row :to
            row :from
            row :subject
          end
          iframe style: 'width: 100%; height: 400px; border: none; margin-top: 14px;',
                 src: html_body_admin_mail_notification_path(mail_notification)
        end

        panel 'Events' do
          pre do
            resource.events.to_yaml
          end
        end
      end
    end
  end

  # rubocop:disable Rails/RenderInline
  member_action :html_body do
    render inline: resource.body
  end
  # rubocop:enable Rails/RenderInline
end
