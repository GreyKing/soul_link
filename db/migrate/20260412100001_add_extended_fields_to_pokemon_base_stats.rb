class AddExtendedFieldsToPokemonBaseStats < ActiveRecord::Migration[8.1]
  def change
    change_table :pokemon_base_stats, bulk: true do |t|
      t.integer :base_experience
      t.integer :height
      t.integer :weight
      t.json    :abilities
      t.integer :base_happiness
      t.integer :capture_rate
      t.integer :gender_rate
      t.string  :growth_rate
      t.json    :egg_groups
      t.string  :genus
      t.text    :flavor_text
      t.boolean :is_legendary, default: false, null: false
      t.boolean :is_mythical, default: false, null: false
      t.integer :hatch_counter
    end
  end
end
