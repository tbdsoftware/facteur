# frozen_string_literal: true

class AddTrackingToFacteurMailings < ActiveRecord::Migration[7.1]
  def change
    add_column :facteur_mailings, :skipped_at, :datetime
    add_column :facteur_mailings, :skip_reason, :string
    add_column :facteur_mailings, :provider_message_ids, :jsonb, default: [], null: false
  end
end
