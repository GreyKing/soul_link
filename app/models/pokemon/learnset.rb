class Pokemon::Learnset < ApplicationRecord
  self.table_name = "pokemon_learnsets"

  belongs_to :pokemon_base_stat, class_name: "Pokemon::BaseStat"
  belongs_to :pokemon_move, class_name: "Pokemon::Move"

  validates :learn_method, presence: true, inclusion: { in: %w[level-up machine egg tutor form-change light-ball-egg] }
  validates :pokemon_base_stat_id, uniqueness: { scope: [:pokemon_move_id, :learn_method] }

  scope :by_method, ->(m) { where(learn_method: m) }
  scope :by_level_range, ->(min, max) { where(learn_method: "level-up", level_learned: min..max) }
end
