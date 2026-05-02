module GymDraftHelper
  # Renders a Discord avatar for the given player on the given run.
  # If an avatar URL is cached on the run (via SoulLinkRun#upsert_avatar!),
  # returns an <img>. Otherwise falls back to a colored circle showing
  # the first letter of the player's display_name. Fallback color is
  # deterministic per discord_user_id, so the same user always renders
  # the same color across sessions.
  def player_avatar_image(run, discord_user_id, size: 32)
    url = run.avatar_for(discord_user_id)
    name = SoulLink::GameState.player_name(discord_user_id).to_s
    if url.present?
      image_tag url,
        alt: name,
        class: "gb-avatar gb-avatar--#{size}"
    else
      initial = name[0]&.upcase || "?"
      color_index = discord_user_id.to_i % 4
      content_tag :span, initial,
        class: "gb-avatar gb-avatar--#{size} gb-avatar--initial gb-avatar--c#{color_index}",
        title: name
    end
  end
end
