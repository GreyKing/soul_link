class GymResult < ApplicationRecord
  belongs_to :soul_link_run
  belongs_to :gym_draft, optional: true

  validates :gym_number, presence: true,
            inclusion: { in: 1..8 },
            uniqueness: { scope: :soul_link_run_id }
  validates :beaten_at, presence: true

  # Real-time UX: dashboard pages subscribed to the run-scoped
  # :dashboard stream get a Turbo refresh broadcast on
  # create/update/destroy, so other players' open dashboards see the
  # gym change without a manual reload. Mirrors the Step 9 KG-2
  # pattern on `SoulLinkPokemon`. Covers manual MARK/UNMARK,
  # post-draft mark-beaten, and the auto-mark path from
  # `SoulLink::GymBeatenCoordinator` — all three create through
  # `gym_results.create!`.
  broadcasts_refreshes_to ->(record) { [ record.soul_link_run, :dashboard ] }

  # Single entry point for "mark gym N beaten" used by every path
  # (draft-page MARK BEATEN, dashboard MARK BEATEN, save-parse
  # auto-mark). Links the completed draft for this gym — explicit
  # `draft:` if given, else the run's most recently completed draft
  # not yet attached to a result — and snapshots its team. Callers
  # own their own guards (uniqueness, suppression, all-4 gate).
  def self.record_beaten!(run, gym_number, draft: nil)
    draft ||= run.gym_drafts
                 .where(status: "complete")
                 .where.missing(:gym_results)
                 .order(updated_at: :desc, id: :desc)
                 .first

    run.transaction do
      result = run.gym_results.create!(
        gym_number: gym_number,
        beaten_at: Time.current,
        gym_draft: draft,
        team_snapshot: draft && snapshot_from_draft(draft)
      )
      run.update!(gyms_defeated: [ run.gyms_defeated, gym_number ].max)
      result
    end
  end

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
