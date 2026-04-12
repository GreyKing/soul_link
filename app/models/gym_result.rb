class GymResult < ApplicationRecord
  belongs_to :soul_link_run
  belongs_to :gym_draft, optional: true

  validates :gym_number, presence: true,
            inclusion: { in: 1..8 },
            uniqueness: { scope: :soul_link_run_id }
  validates :beaten_at, presence: true

  def self.snapshot_from_groups(groups)
    players = SoulLink::GameState.players
    {
      "groups" => groups.map do |group|
        {
          "group_id" => group.id,
          "nickname" => group.nickname,
          "location" => group.location,
          "pokemon" => group.soul_link_pokemon.map do |p|
            player = players.find { |pl| pl["discord_user_id"] == p.discord_user_id }
            {
              "discord_user_id" => p.discord_user_id.to_s,
              "player_name" => player&.[]("display_name") || p.discord_user_id.to_s,
              "species" => p.species,
              "level" => p.level,
              "ability" => p.ability,
              "nature" => p.nature
            }
          end
        }
      end
    }
  end

  def self.snapshot_from_draft(draft)
    group_ids = draft.final_team_group_ids
    groups = draft.soul_link_run.soul_link_pokemon_groups
                  .where(id: group_ids)
                  .includes(:soul_link_pokemon)
    snapshot_from_groups(groups)
  end

  def self.snapshot_from_group_ids(run, group_ids)
    groups = run.soul_link_pokemon_groups
                .where(id: group_ids)
                .includes(:soul_link_pokemon)
    snapshot_from_groups(groups)
  end
end
