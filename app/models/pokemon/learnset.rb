class Pokemon::Learnset < ApplicationRecord
  self.table_name = "pokemon_learnsets"

  belongs_to :pokemon_base_stat, class_name: "Pokemon::BaseStat"
  belongs_to :pokemon_move, class_name: "Pokemon::Move"

  validates :learn_method, presence: true, inclusion: { in: %w[level-up machine egg tutor] }
  validates :pokemon_base_stat_id, uniqueness: { scope: [:pokemon_move_id, :learn_method] }
end
