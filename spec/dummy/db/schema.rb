# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_11_10_205402) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "facteur_mailings", force: :cascade do |t|
    t.string "resource_type"
    t.bigint "resource_id"
    t.string "mailer_klass"
    t.string "mailer_method"
    t.jsonb "mailer_params"
    t.datetime "sent_at"
    t.string "subject"
    t.string "from"
    t.string "to"
    t.text "body"
    t.datetime "delivered_at"
    t.jsonb "events"
    t.datetime "processed_at"
    t.datetime "opened_at"
    t.datetime "clicked_at"
    t.datetime "error_at"
    t.string "error_msg"
    t.integer "status", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "skipped_at"
    t.string "skip_reason"
    t.jsonb "provider_message_ids", default: [], null: false
    t.index ["resource_type", "resource_id"], name: "index_facteur_mailings_on_resource"
  end

end
