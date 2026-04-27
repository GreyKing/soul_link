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

ActiveRecord::Schema[8.1].define(version: 2026_04_26_233223) do
  create_table "gym_drafts", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "current_player_index", default: 0, null: false
    t.integer "current_round", default: 0, null: false
    t.json "pick_order"
    t.bigint "soul_link_run_id", null: false
    t.json "state_data"
    t.string "status", default: "lobby", null: false
    t.datetime "updated_at", null: false
    t.index ["soul_link_run_id", "status"], name: "index_gym_drafts_on_soul_link_run_id_and_status"
    t.index ["soul_link_run_id"], name: "index_gym_drafts_on_soul_link_run_id"
  end

  create_table "gym_results", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "beaten_at", null: false
    t.datetime "created_at", null: false
    t.bigint "gym_draft_id"
    t.integer "gym_number", null: false
    t.bigint "soul_link_run_id", null: false
    t.json "team_snapshot"
    t.datetime "updated_at", null: false
    t.index ["gym_draft_id"], name: "index_gym_results_on_gym_draft_id"
    t.index ["soul_link_run_id", "gym_number"], name: "index_gym_results_on_soul_link_run_id_and_gym_number", unique: true
    t.index ["soul_link_run_id"], name: "index_gym_results_on_soul_link_run_id"
  end

  create_table "gym_schedules", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "discord_channel_id"
    t.bigint "discord_message_id"
    t.bigint "gym_draft_id"
    t.bigint "proposed_by", null: false
    t.datetime "scheduled_at", null: false
    t.bigint "soul_link_run_id", null: false
    t.json "state_data"
    t.string "status", default: "proposed", null: false
    t.datetime "updated_at", null: false
    t.index ["gym_draft_id"], name: "index_gym_schedules_on_gym_draft_id"
    t.index ["soul_link_run_id", "status"], name: "index_gym_schedules_on_soul_link_run_id_and_status"
    t.index ["soul_link_run_id"], name: "index_gym_schedules_on_soul_link_run_id"
  end

  create_table "pokemon_base_stats", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.json "abilities"
    t.integer "atk", null: false
    t.integer "base_experience"
    t.integer "base_happiness"
    t.integer "capture_rate"
    t.datetime "created_at", null: false
    t.integer "def_stat", null: false
    t.json "egg_groups"
    t.text "flavor_text"
    t.integer "gender_rate"
    t.string "genus"
    t.string "growth_rate"
    t.integer "hatch_counter"
    t.integer "height"
    t.integer "hp", null: false
    t.boolean "is_legendary", default: false, null: false
    t.boolean "is_mythical", default: false, null: false
    t.integer "national_dex_number", null: false
    t.integer "spa", null: false
    t.integer "spd", null: false
    t.integer "spe", null: false
    t.string "species", null: false
    t.string "type1", null: false
    t.string "type2"
    t.datetime "updated_at", null: false
    t.integer "weight"
    t.index ["national_dex_number"], name: "index_pokemon_base_stats_on_national_dex_number", unique: true
    t.index ["species"], name: "index_pokemon_base_stats_on_species", unique: true
  end

  create_table "pokemon_learnsets", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "learn_method", null: false
    t.integer "level_learned"
    t.bigint "pokemon_base_stat_id", null: false
    t.bigint "pokemon_move_id", null: false
    t.datetime "updated_at", null: false
    t.index ["pokemon_base_stat_id", "pokemon_move_id", "learn_method"], name: "idx_learnset_unique", unique: true
    t.index ["pokemon_base_stat_id"], name: "index_pokemon_learnsets_on_pokemon_base_stat_id"
    t.index ["pokemon_move_id"], name: "index_pokemon_learnsets_on_pokemon_move_id"
  end

  create_table "pokemon_moves", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.integer "accuracy"
    t.string "ailment"
    t.integer "ailment_chance", default: 0, null: false
    t.string "category", null: false
    t.datetime "created_at", null: false
    t.integer "crit_rate", default: 0, null: false
    t.integer "drain", default: 0, null: false
    t.text "effect"
    t.text "flavor_text"
    t.integer "flinch_chance", default: 0, null: false
    t.integer "healing", default: 0, null: false
    t.integer "max_hits"
    t.integer "min_hits"
    t.string "move_type", null: false
    t.string "name", null: false
    t.integer "power"
    t.integer "pp"
    t.integer "priority", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_pokemon_moves_on_name", unique: true
  end

  create_table "soul_link_emulator_sessions", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "discord_user_id"
    t.string "error_message"
    t.string "rom_path"
    t.binary "save_data", size: :long
    t.string "seed", null: false
    t.bigint "soul_link_run_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["soul_link_run_id", "discord_user_id"], name: "idx_emu_session_run_user", unique: true
    t.index ["soul_link_run_id", "status"], name: "idx_emu_session_run_status"
    t.index ["soul_link_run_id"], name: "index_soul_link_emulator_sessions_on_soul_link_run_id"
  end

  create_table "soul_link_pokemon", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.string "ability"
    t.datetime "caught_at"
    t.datetime "created_at", null: false
    t.datetime "died_at"
    t.bigint "discord_user_id", null: false
    t.integer "evolution_level"
    t.integer "level"
    t.string "location", null: false
    t.string "name", null: false
    t.string "nature"
    t.bigint "soul_link_pokemon_group_id"
    t.bigint "soul_link_run_id", null: false
    t.string "species", null: false
    t.string "status", default: "caught", null: false
    t.datetime "updated_at", null: false
    t.index ["soul_link_pokemon_group_id", "discord_user_id"], name: "index_pokemon_on_group_and_user", unique: true
    t.index ["soul_link_pokemon_group_id"], name: "index_soul_link_pokemon_on_soul_link_pokemon_group_id"
    t.index ["soul_link_run_id", "status"], name: "index_soul_link_pokemon_on_soul_link_run_id_and_status"
    t.index ["soul_link_run_id"], name: "index_soul_link_pokemon_on_soul_link_run_id"
    t.index ["status"], name: "index_soul_link_pokemon_on_status"
  end

  create_table "soul_link_pokemon_groups", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "caught_at"
    t.datetime "created_at", null: false
    t.datetime "died_at"
    t.text "eulogy"
    t.string "location", null: false
    t.string "nickname", null: false
    t.integer "position", null: false
    t.bigint "soul_link_run_id", null: false
    t.string "status", default: "caught", null: false
    t.datetime "updated_at", null: false
    t.index ["soul_link_run_id", "nickname"], name: "idx_on_soul_link_run_id_nickname_4d742b8831"
    t.index ["soul_link_run_id", "status"], name: "index_soul_link_pokemon_groups_on_soul_link_run_id_and_status"
    t.index ["soul_link_run_id"], name: "index_soul_link_pokemon_groups_on_soul_link_run_id"
  end

  create_table "soul_link_runs", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "catches_channel_id"
    t.bigint "catches_panel_message_id"
    t.bigint "category_id"
    t.datetime "created_at", null: false
    t.bigint "deaths_channel_id"
    t.bigint "deaths_panel_message_id"
    t.bigint "general_channel_id"
    t.bigint "guild_id", null: false
    t.integer "gyms_defeated", default: 0, null: false
    t.integer "run_number", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_soul_link_runs_on_active"
    t.index ["guild_id", "active"], name: "index_soul_link_runs_on_guild_id_and_active"
    t.index ["guild_id", "run_number"], name: "index_soul_link_runs_on_guild_id_and_run_number", unique: true
  end

  create_table "soul_link_team_slots", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "position", null: false
    t.bigint "soul_link_pokemon_group_id", null: false
    t.bigint "soul_link_team_id", null: false
    t.datetime "updated_at", null: false
    t.index ["soul_link_pokemon_group_id"], name: "index_soul_link_team_slots_on_soul_link_pokemon_group_id"
    t.index ["soul_link_team_id", "position"], name: "index_team_slots_on_team_and_position", unique: true
    t.index ["soul_link_team_id", "soul_link_pokemon_group_id"], name: "index_team_slots_on_team_and_group", unique: true
    t.index ["soul_link_team_id"], name: "index_soul_link_team_slots_on_soul_link_team_id"
  end

  create_table "soul_link_teams", charset: "utf8mb4", collation: "utf8mb4_0900_ai_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "discord_user_id", null: false
    t.string "label"
    t.bigint "soul_link_run_id", null: false
    t.datetime "updated_at", null: false
    t.index ["soul_link_run_id", "discord_user_id"], name: "index_teams_on_run_and_user", unique: true
    t.index ["soul_link_run_id"], name: "index_soul_link_teams_on_soul_link_run_id"
  end

  add_foreign_key "gym_drafts", "soul_link_runs"
  add_foreign_key "gym_results", "gym_drafts"
  add_foreign_key "gym_results", "soul_link_runs"
  add_foreign_key "gym_schedules", "gym_drafts"
  add_foreign_key "gym_schedules", "soul_link_runs"
  add_foreign_key "pokemon_learnsets", "pokemon_base_stats"
  add_foreign_key "pokemon_learnsets", "pokemon_moves"
  add_foreign_key "soul_link_emulator_sessions", "soul_link_runs"
  add_foreign_key "soul_link_pokemon", "soul_link_pokemon_groups"
  add_foreign_key "soul_link_pokemon", "soul_link_runs"
  add_foreign_key "soul_link_pokemon_groups", "soul_link_runs"
  add_foreign_key "soul_link_team_slots", "soul_link_pokemon_groups"
  add_foreign_key "soul_link_team_slots", "soul_link_teams"
  add_foreign_key "soul_link_teams", "soul_link_runs"
end
