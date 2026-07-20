require "discordrb"

module SoulLink
  # Owns the live-updating "new catch" message in the run's catches channel.
  #
  # One Discord message per catch group. The group's
  # `discord_catch_message_id` is both the idempotency key (non-nil means
  # already posted) and the address for subsequent edits — so calling
  # `post_or_update` any number of times produces exactly one message.
  #
  # Embed shape mirrors `GymPollMessage`: a plain hash built here, handed to
  # the REST layer positionally below.
  #
  # Fire-and-forget, matching the `DiscordNotifier` contract: every failure
  # mode is swallowed and logged at warn level. Callers need no rescue.
  class CatchMessage
    EMBED_COLOR      = 0x57F287  # green — matches the "caught" status colour
    DEAD_EMBED_COLOR = 0xED4245  # red — matches the "dead" status colour
    NOT_CAUGHT       = "— not caught yet —".freeze

    class << self
      def post_or_update(group)
        return if group.nil?

        run = group.soul_link_run
        return if run.nil? || run.catches_channel_id.blank?

        token = resolve_token
        return if token.blank?

        if group.discord_catch_message_id.present?
          edit(token, run, group)
        else
          post(token, run, group)
        end
      rescue StandardError => e
        log_failure(e, group)
        nil
      end

      # ── embed construction ───────────────────────────────────────────
      # Public for the same reason GymPollMessage's are: the pieces are
      # consumed by other callers (the catch button handler) as well as by
      # post/edit below.

      def embed(group)
        dead = group.dead?
        {
          title: dead ? "💀 #{location_label(group)}" : "🎯 NEW CATCH — #{location_label(group)}",
          description: player_lines(group).join("\n"),
          color: dead ? DEAD_EMBED_COLOR : EMBED_COLOR
        }
      end

      # A dead group freezes as history: recolored embed, no buttons.
      def components(group)
        return [] if group.dead?

        [ {
          type: 1,
          components: [
            {
              type: 2,
              style: 1,
              label: "ADD MY POKEMON",
              custom_id: "soul_link:catch_add:#{group.id}"
            },
            {
              type: 2,
              style: 2,
              label: "🔄 REFRESH",
              custom_id: "soul_link:catch_refresh:#{group.id}"
            }
          ]
        } ]
      end

      private

      # POSITIONAL args — discordrb's API methods accept no keywords. Passing
      # `embeds:`/`components:` would collapse into a Hash bound to `tts` and
      # Discord would reject the payload. Signature:
      #   create_message(token, channel_id, message, tts, embeds, nonce,
      #                  attachments, allowed_mentions, message_reference,
      #                  components, flags, enforce_nonce)
      def post(token, run, group)
        response = Discordrb::API::Channel.create_message(
          token,
          run.catches_channel_id,
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
          # Nothing to store, so the next call would post a duplicate. Loud
          # in the log rather than silent, per the fire-and-forget contract.
          Rails.logger.warn(
            "CatchMessage posted but could not parse a message id (group=#{group.id})"
          )
          return
        end

        group.update_columns(discord_catch_message_id: message_id)
      end

      #   edit_message(token, channel_id, message_id, message, mentions,
      #                embeds, components, flags)
      def edit(token, run, group)
        Discordrb::API::Channel.edit_message(
          token,
          run.catches_channel_id,
          group.discord_catch_message_id,
          "",                    # message
          nil,                   # mentions
          [ embed(group) ],      # embeds
          components(group)      # components
        )
      rescue RestClient::NotFound, Discordrb::Errors::UnknownMessage
        # The message was deleted in Discord. Clear the stale id and post
        # once more. A failure on that re-post falls through to the outer
        # rescue in `post_or_update` — we never loop.
        #
        # UnknownMessage (code 10008) is the case that actually fires:
        # `Discordrb::API.request` intercepts every RestClient::Exception
        # with a body and re-raises a converted CodeError, which does NOT
        # inherit from RestClient::NotFound. RestClient::NotFound is kept
        # because the conversion is skipped when the response body is
        # empty, so that path remains reachable.
        group.update_columns(discord_catch_message_id: nil)
        post(token, run, group)
      end

      # One line per registered player: filled slots show species + level,
      # empty slots show the NOT_CAUGHT placeholder. Players come from
      # GameState so the roster stays the single source of truth.
      def player_lines(group)
        by_uid = group.soul_link_pokemon.index_by(&:discord_user_id)

        SoulLink::GameState.players.map do |player|
          uid = player["discord_user_id"]
          pokemon = by_uid[uid]
          name = player["display_name"] || uid.to_s
          "**#{name}** — #{pokemon ? pokemon_summary(pokemon) : NOT_CAUGHT}"
        end
      end

      def pokemon_summary(pokemon)
        level = pokemon.level.present? ? " Lv #{pokemon.level}" : ""
        "#{pokemon.species}#{level}"
      end

      # "Route 205 • \"TOMMY\"". `location_name` already falls back to
      # `titleize` for unknown keys, so no nil guard is needed here.
      def location_label(group)
        "#{SoulLink::GameState.location_name(group.location)} • \"#{group.nickname}\""
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
          "CatchMessage failed: #{error.class} #{error.message} (group=#{group&.id})"
        )
      end

      # Mirrors DiscordNotifier#resolve_token.
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
