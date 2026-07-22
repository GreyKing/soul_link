require "discordrb"

module SoulLink
  # Owns the live-updating "RIP" message in the run's deaths channel — the
  # death-side twin of `CatchMessage`. One Discord message per dead group.
  #
  # The group's `discord_death_message_id` is both the idempotency key (non-nil
  # means already posted) and the address for subsequent edits, so calling
  # `post_or_update` any number of times produces exactly one message.
  #
  # Unlike the catch embed — which strips its buttons once dead to freeze as
  # history — a death embed is *always* terminal, so it keeps its 🔄 REFRESH
  # button as a manual re-sync escape hatch.
  #
  # Fire-and-forget, matching the `CatchMessage`/`DiscordNotifier` contract:
  # every failure mode is swallowed and logged at warn level. Callers need no
  # rescue.
  class DeathMessage
    EMBED_COLOR = 0xED4245  # red — matches the "dead" status colour

    class << self
      def post_or_update(group)
        return if group.nil?

        run = group.soul_link_run
        return if run.nil? || run.deaths_channel_id.blank?

        token = resolve_token
        return if token.blank?

        if group.discord_death_message_id.present?
          edit(token, run, group)
        else
          post(token, run, group)
        end
      rescue StandardError => e
        log_failure(e, group)
        nil
      end

      # Remove the death message from Discord and forget its id. Callers must
      # invoke this BEFORE destroying the group row — the id lives on the group.
      # Fire-and-forget, matching post_or_update: every failure is swallowed.
      def delete(group)
        return if group.nil? || group.discord_death_message_id.blank?

        run = group.soul_link_run
        return if run.nil? || run.deaths_channel_id.blank?

        token = resolve_token
        return if token.blank?

        Discordrb::API::Channel.delete_message(
          token,
          run.deaths_channel_id,
          group.discord_death_message_id
        )
        group.update_columns(discord_death_message_id: nil)
      rescue StandardError => e
        log_failure(e, group)
        nil
      end

      # ── embed construction ───────────────────────────────────────────

      def embed(group)
        {
          title: "💀 RIP \"#{group.nickname}\" — #{SoulLink::GameState.location_name(group.location)}",
          description: death_lines(group).join("\n"),
          color: EMBED_COLOR
        }
      end

      # A death embed is terminal but stays refreshable: one 🔄 REFRESH button.
      def components(group)
        [ {
          type: 1,
          components: [
            {
              type: 2,
              style: 2,
              label: "🔄 REFRESH",
              custom_id: "soul_link:death_refresh:#{group.id}"
            }
          ]
        } ]
      end

      private

      # POSITIONAL args — discordrb's API methods accept no keywords. See
      # CatchMessage#post for the full signature rationale.
      def post(token, run, group)
        response = Discordrb::API::Channel.create_message(
          token,
          run.deaths_channel_id,
          "",                    # message
          false,                 # tts
          [ embed(group) ],      # embeds
          nil,                   # nonce
          nil,                   # attachments
          nil,                   # allowed_mentions
          nil,                   # message_reference
          components(group)      # components
        )
        message_id = parse_message_id(response)
        if message_id.nil?
          Rails.logger.warn(
            "DeathMessage posted but could not parse a message id (group=#{group.id})"
          )
          return
        end

        group.update_columns(discord_death_message_id: message_id)
      end

      def edit(token, run, group)
        Discordrb::API::Channel.edit_message(
          token,
          run.deaths_channel_id,
          group.discord_death_message_id,
          "",                    # message
          nil,                   # mentions
          [ embed(group) ],      # embeds
          components(group)      # components
        )
      rescue RestClient::NotFound, Discordrb::Errors::UnknownMessage
        # The message was deleted in Discord. Clear the stale id and post once
        # more; a failure on that re-post falls through to the outer rescue in
        # post_or_update — we never loop. See CatchMessage#edit for why both
        # exception classes are caught.
        group.update_columns(discord_death_message_id: nil)
        post(token, run, group)
      end

      # One line per fallen Pokemon in the group, then the eulogy if present.
      def death_lines(group)
        lines = group.soul_link_pokemon.map do |pokemon|
          "**#{SoulLink::GameState.player_name(pokemon.discord_user_id)}** — #{pokemon.species}"
        end
        lines << "📝 *#{group.eulogy}*" if group.eulogy.present?
        lines
      end

      # discordrb returns a RestClient::Response, which subclasses String.
      def parse_message_id(response)
        body = response.is_a?(String) ? JSON.parse(response) : response
        id = body.is_a?(Hash) ? (body["id"] || body[:id]) : nil
        id.presence && id.to_i
      rescue JSON::ParserError
        nil
      end

      def log_failure(error, group)
        Rails.logger.warn(
          "DeathMessage failed: #{error.class} #{error.message} (group=#{group&.id})"
        )
      end

      # Mirrors CatchMessage#resolve_token / DiscordNotifier#resolve_token.
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
