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

ActiveRecord::Schema[8.1].define(version: 2026_02_02_164130) do
  create_table "soul_link_pokemon", force: :cascade do |t|
    t.datetime "caught_at"
    t.datetime "created_at", null: false
    t.datetime "died_at"
    t.bigint "discord_user_id", null: false
    t.string "location", null: false
    t.string "name", null: false
    t.integer "soul_link_run_id", null: false
    t.string "status", default: "caught", null: false
    t.datetime "updated_at", null: false
    t.index ["soul_link_run_id", "status"], name: "index_soul_link_pokemon_on_soul_link_run_id_and_status"
    t.index ["soul_link_run_id"], name: "index_soul_link_pokemon_on_soul_link_run_id"
    t.index ["status"], name: "index_soul_link_pokemon_on_status"
  end

  create_table "soul_link_runs", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "catches_channel_id", null: false
    t.bigint "catches_panel_message_id"
    t.bigint "category_id", null: false
    t.datetime "created_at", null: false
    t.bigint "deaths_channel_id", null: false
    t.bigint "deaths_panel_message_id"
    t.bigint "general_channel_id", null: false
    t.integer "run_number", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_soul_link_runs_on_active"
    t.index ["run_number"], name: "index_soul_link_runs_on_run_number", unique: true
  end

  add_foreign_key "soul_link_pokemon", "soul_link_runs"
end
