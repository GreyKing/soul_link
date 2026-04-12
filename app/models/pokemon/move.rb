class Pokemon::Move < ApplicationRecord
  self.table_name = "pokemon_moves"

  has_many :pokemon_learnsets, class_name: "Pokemon::Learnset", foreign_key: :pokemon_move_id, dependent: :destroy
  has_many :learners, through: :pokemon_learnsets, source: :pokemon_base_stat

  validates :name, presence: true, uniqueness: true
  validates :move_type, presence: true
  validates :category, presence: true, inclusion: { in: %w[physical special status] }

  scope :damaging, -> { where(category: %w[physical special]) }
  scope :by_type, ->(type) { where(move_type: type) }
end
