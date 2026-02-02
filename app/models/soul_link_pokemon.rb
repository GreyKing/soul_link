class SoulLinkPokemon < ApplicationRecord
  self.table_name = 'soul_link_pokemon'  # Add this line

  belongs_to :soul_link_run

  validates :name, :location, :discord_user_id, presence: true
  validates :status, inclusion: { in: %w[caught dead] }

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