class SoulLinkTeamSlot < ApplicationRecord
  belongs_to :soul_link_team
  belongs_to :soul_link_pokemon_group

  validates :position, presence: true,
    inclusion: { in: 1..SoulLinkTeam::MAX_SLOTS, message: "must be between 1 and #{SoulLinkTeam::MAX_SLOTS}" }
  validates :position, uniqueness: { scope: :soul_link_team_id }
  validates :soul_link_pokemon_group_id, uniqueness: { scope: :soul_link_team_id }
end
