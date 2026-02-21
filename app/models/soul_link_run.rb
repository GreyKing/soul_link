class SoulLinkRun < ApplicationRecord
  has_many :soul_link_pokemon_groups, dependent: :destroy
  has_many :soul_link_pokemon, dependent: :destroy

  validates :run_number, presence: true, uniqueness: { scope: :guild_id }
  validates :guild_id, presence: true
  validates :category_id, :general_channel_id, :catches_channel_id, :deaths_channel_id, presence: true

  scope :active, -> { where(active: true) }
  scope :inactive, -> { where(active: false) }
  scope :for_guild, ->(guild_id) { where(guild_id: guild_id) }

  def self.current(guild_id)
    active.for_guild(guild_id).order(run_number: :desc).first
  end

  # Group-based queries (primary — used by panels)
  def caught_groups
    soul_link_pokemon_groups.caught.order(created_at: :asc)
  end

  def dead_groups
    soul_link_pokemon_groups.dead.order(died_at: :asc)
  end

  # Legacy individual queries (kept for backward compatibility)
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
