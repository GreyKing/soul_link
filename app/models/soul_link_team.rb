class SoulLinkTeam < ApplicationRecord
  belongs_to :soul_link_run
  has_many :soul_link_team_slots, -> { order(:position) }, dependent: :destroy
  has_many :soul_link_pokemon_groups, through: :soul_link_team_slots

  validates :discord_user_id, presence: true
  validates :discord_user_id, uniqueness: { scope: :soul_link_run_id }

  MAX_SLOTS = 6

  # Atomically replace all team slots with the given group_ids (in order).
  # Empty array clears the team.
  def replace_slots!(group_ids)
    group_ids = group_ids.first(MAX_SLOTS).map(&:to_i)

    transaction do
      soul_link_team_slots.delete_all

      group_ids.each_with_index do |group_id, idx|
        soul_link_team_slots.create!(
          soul_link_pokemon_group_id: group_id,
          position: idx + 1
        )
      end
    end
  end

  def player_name
    SoulLink::GameState.player_name(discord_user_id)
  end
end
