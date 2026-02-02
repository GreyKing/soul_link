class SoulLinkRun < ApplicationRecord
  has_many :soul_link_pokemon, dependent: :destroy

  validates :run_number, presence: true, uniqueness: true
  validates :category_id, :general_channel_id, :catches_channel_id, :deaths_channel_id, presence: true

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }

  def self.current
    active.order(run_number: :desc).first
  end

  def catches
    soul_link_pokemon.where(status: 'caught').order(created_at: :asc)
  end

  def deaths
    soul_link_pokemon.where(status: 'dead').order(died_at: :asc)
  end

  def deactivate!
    update!(active: false)
  end
end