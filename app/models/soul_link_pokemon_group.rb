class SoulLinkPokemonGroup < ApplicationRecord
  self.table_name = 'soul_link_pokemon_groups'

  belongs_to :soul_link_run
  has_many :soul_link_pokemon, dependent: :destroy
  has_many :soul_link_team_slots, dependent: :destroy

  validates :nickname, :location, presence: true
  validates :status, inclusion: { in: %w[caught dead] }

  scope :caught, -> { where(status: 'caught') }
  scope :dead, -> { where(status: 'dead') }

  before_create :set_caught_at, if: -> { status == 'caught' }
  after_update :remove_team_slots_on_death, if: -> { saved_change_to_status? && dead? }

  def mark_as_dead!(death_location: nil, eulogy: nil)
    transaction do
      update!(
        status: 'dead',
        died_at: Time.current,
        location: death_location || location,
        eulogy: eulogy.presence
      )

      soul_link_pokemon.each do |pokemon|
        pokemon.update!(
          status: 'dead',
          died_at: Time.current
        )
      end
    end
  end

  def caught?
    status == 'caught'
  end

  def dead?
    status == 'dead'
  end

  def species_for(discord_user_id)
    soul_link_pokemon.find_by(discord_user_id: discord_user_id)
  end

  def missing_players
    registered_ids = SoulLink::GameState.player_ids
    assigned_ids = soul_link_pokemon.pluck(:discord_user_id)
    registered_ids - assigned_ids
  end

  def complete?
    missing_players.empty?
  end

  private

  def set_caught_at
    self.caught_at = Time.current
  end

  def remove_team_slots_on_death
    soul_link_team_slots.destroy_all
  end
end
