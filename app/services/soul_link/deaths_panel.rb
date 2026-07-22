require "discordrb"

module SoulLink
  # The run-level "💀 Fallen Pokemon" roster panel. Stateless renderer + REST
  # editor so the WEBSITE can keep the panel in sync — the bot's old
  # `channel.load_message(...).edit(...)` only worked inside the bot process,
  # which is why website-driven deaths left the panel stale.
  #
  # This owns the panel's embed + buttons (the single source of truth): the bot
  # creates the panel via `/post_panels` using `embed`/`components` here, and
  # both the bot and the web request path re-sync it through `refresh`.
  #
  # `refresh` is EDIT-ONLY: it never creates a panel. When no panel exists yet
  # (`deaths_panel_message_id` blank) it is a silent no-op — the panel is born
  # from `/post_panels`, not from a death. Fire-and-forget like DeathMessage.
  class DeathsPanel
    EMBED_COLOR = 0xff0000  # red

    class << self
      def refresh(run)
        return if run.nil? || run.deaths_panel_message_id.blank?
        return if run.deaths_channel_id.blank?

        token = resolve_token
        return if token.blank?

        edit(token, run)
      rescue StandardError => e
        log_failure(e, run)
        nil
      end

      # ── embed / components (also consumed by the bot's post_deaths_panel) ──

      def embed(run)
        groups = run.dead_groups.includes(:soul_link_pokemon)

        {
          title: "💀 Fallen Pokemon",
          description: description_for(groups),
          color: EMBED_COLOR,
          footer: { text: "Run ##{run.run_number} | Groups: #{groups.count}" },
          timestamp: Time.now.utc.iso8601
        }
      end

      def components
        [ {
          type: 1,
          components: [
            {
              type: 2,
              style: 4,   # Danger (red)
              label: "💀 Move Caught to Deaths",
              custom_id: "soul_link:move_to_deaths"
            },
            {
              type: 2,
              style: 2,   # Secondary (gray)
              label: "➕ Add Uncaught Death",
              custom_id: "soul_link:add_uncaught_death"
            },
            {
              type: 2,
              style: 2,   # Secondary (gray)
              label: "🔄 REFRESH",
              custom_id: "soul_link:deaths_refresh"
            }
          ]
        } ]
      end

      private

      def description_for(groups)
        return "*No deaths yet. Stay safe out there!*" if groups.empty?

        groups.map.with_index(1) do |group, idx|
          lines = [ "**#{idx}.** #{group.nickname} *(#{SoulLink::GameState.location_name(group.location)})*" ]

          group.soul_link_pokemon.each do |pokemon|
            lines << "   #{SoulLink::GameState.player_name(pokemon.discord_user_id)}: #{pokemon.species}"
          end

          lines << "   📝 *#{group.eulogy}*" if group.eulogy.present?

          lines.join("\n")
        end.join("\n\n")
      end

      def edit(token, run)
        Discordrb::API::Channel.edit_message(
          token,
          run.deaths_channel_id,
          run.deaths_panel_message_id,
          "",             # message
          nil,            # mentions
          [ embed(run) ], # embeds
          components      # components
        )
      rescue RestClient::NotFound, Discordrb::Errors::UnknownMessage
        # Panel message was deleted in Discord. Forget the stale id so a future
        # /post_panels re-creates cleanly — refresh can't recreate it itself.
        run.update_columns(deaths_panel_message_id: nil)
      end

      def log_failure(error, run)
        Rails.logger.warn(
          "DeathsPanel failed: #{error.class} #{error.message} (run=#{run&.id})"
        )
      end

      # Mirrors DeathMessage#resolve_token.
      def resolve_token
        creds = Rails.application.credentials.discord
        return nil if creds.nil?
        token = creds.is_a?(Hash) ? creds[:token] : creds.try(:[], :token)
        return nil if token.blank?
        "Bot #{token}"
      end
    end
  end
end
