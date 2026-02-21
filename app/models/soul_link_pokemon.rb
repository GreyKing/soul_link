class SoulLinkPokemon < ApplicationRecord
  self.table_name = 'soul_link_pokemon'

  belongs_to :soul_link_run
  belongs_to :soul_link_pokemon_group, optional: true

  validates :discord_user_id, presence: true
  validates :status, inclusion: { in: %w[caught dead] }
  validates :species, presence: true, if: -> { soul_link_pokemon_group_id.present? }
  validates :discord_user_id, uniqueness: { scope: :soul_link_pokemon_group_id }, if: -> { soul_link_pokemon_group_id.present? }

  # Legacy: name/location still validated for backward compat during migration
  validates :name, presence: true
  validates :location, presence: true

  before_create :set_caught_at, if: -> { status == 'caught' }

  def mark_as_dead!(location: nil)
    update!(
      status: 'dead',
      died_at: Time.current,
      location: location || self.location
    )
  end

  def caught?
    status == 'caught'
  end

  def dead?
    status == 'dead'
  end

  private

  def set_caught_at
    self.caught_at = Time.current
  end
end
