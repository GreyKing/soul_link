class Pokemon::BaseStat < ApplicationRecord
  self.table_name = "pokemon_base_stats"

  has_many :pokemon_learnsets, class_name: "Pokemon::Learnset", foreign_key: :pokemon_base_stat_id, dependent: :destroy
  has_many :moves, through: :pokemon_learnsets, source: :pokemon_move

  validates :species, presence: true, uniqueness: true
  validates :national_dex_number, presence: true, uniqueness: true
  validates :hp, :atk, :def_stat, :spa, :spd, :spe, presence: true
  validates :type1, presence: true
  validates :national_dex_number, inclusion: { in: 1..493 }

  scope :by_type, ->(t) { where(type1: t).or(where(type2: t)) }

  def base_stat_total
    hp + atk + def_stat + spa + spd + spe
  end

  def types
    [type1, type2].compact
  end
end
