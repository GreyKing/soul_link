require "discordrb"

module SoulLink
  # Outgoing Discord-message service for run-event notifications. Mirrors
  # `SoulLink::DiscordApi`'s shape (REST wrapper called from the Rails
  # process) but is class-only — no per-call setup, no instance state.
  #
  # Architect-locked: this service does NOT load the Discord-bot
  # god-object (`SoulLink::DiscordBot`). The bot owns slash commands and
  # panel updates; outgoing notifications fire directly from the request
  # path via `Discordrb::API::Channel.create_message`. Bot decomposition
  # is a separate future step.
  #
  # All public methods are fire-and-forget: they swallow nil-run / blank-
  # channel / network errors silently (logged at warn level), and never
  # raise. Callers (coordinators, controllers) don't need rescue blocks.
  #
  # Tests stub `Discordrb::API::Channel.create_message` to avoid real
  # HTTP calls — see `test/services/soul_link/discord_notifier_test.rb`.
  class DiscordNotifier
    class << self
      # Catch-event surface (CatchCoordinator). `off_feed: true` flags
      # catches surfaced from the PC-box diff path (Step 18) rather than
      # from the active party.
      def notify_catch(run, player_uid, species, route, level, off_feed: false)
        return if run.nil?

        channel_id = run.catches_channel_id
        return if channel_id.blank?

        player = SoulLink::GameState.player_name(player_uid)
        suffix = off_feed ? " [off-feed]" : ""
        content = "#{player} just caught a #{species} on #{route} (Lv #{level})#{suffix}"

        send_message(channel_id, content, run: run, method_name: __method__)
      end

      # Per-player gym-progress event (GymBeatenCoordinator). Fires once
      # per BadgeGained event, before the all-4 gate is evaluated.
      def notify_gym_player_progress(run, gym_number, player_uid)
        return if run.nil?

        channel_id = run.general_channel_id
        return if channel_id.blank?

        player = SoulLink::GameState.player_name(player_uid)
        gym = SoulLink::GameState.gym_info_by_number(gym_number) || {}
        leader = gym["leader"] || "?"
        town = SoulLink::GameState.location_name(gym["location"])
        content = "#{player} earned the badge from Gym #{gym_number} (#{leader}, #{town})"

        send_message(channel_id, content, run: run, method_name: __method__)
      end

      # Team-level gym-beaten event. Fires from GymBeatenCoordinator when
      # the all-4 AND-gate flips a gym (was_marked → marked transition),
      # and from GymProgressController#update on manual MARK BEATEN.
      def notify_gym_team_beaten(run, gym_number)
        return if run.nil?

        channel_id = run.general_channel_id
        return if channel_id.blank?

        gym = SoulLink::GameState.gym_info_by_number(gym_number) || {}
        leader = gym["leader"] || "?"
        town = SoulLink::GameState.location_name(gym["location"])
        content = "🏅 Gym #{gym_number} (#{leader}, #{town}) beaten by the team!"

        send_message(channel_id, content, run: run, method_name: __method__)
      end

      # Run-ending wipe event (WipeCoordinator). Fires once per nil→Time
      # `wiped_at` transition. `route` is the deceased Pokemon's location
      # (the alive→dead transition that triggered the wipe).
      def notify_wipe(run, player_uid, route)
        return if run.nil?

        channel_id = run.general_channel_id
        return if channel_id.blank?

        player = SoulLink::GameState.player_name(player_uid)
        content = "💀💀💀 RUN ENDED — #{player} wiped on #{route}"

        send_message(channel_id, content, run: run, method_name: __method__)
      end

      # Hall-of-Fame run-completion event (HallOfFameCoordinator). Fires
      # once when `completed_at` flips nil→Time. Closes KG-17.
      def notify_run_complete(run)
        return if run.nil?

        channel_id = run.general_channel_id
        return if channel_id.blank?

        content = "🏆 HALL OF FAME — Run ##{run.run_number} complete!"

        send_message(channel_id, content, run: run, method_name: __method__)
      end

      private

      # Belt-and-suspenders rescue: the specific REST/socket exceptions
      # document the expected failure modes; the trailing StandardError
      # is the safety net so coordinators / controllers never see an
      # exception bubble out of a notification call.
      def send_message(channel_id, content, run:, method_name:)
        token = resolve_token
        return if token.blank?  # tests / unconfigured envs

        Discordrb::API::Channel.create_message(token, channel_id, content)
      rescue RestClient::ExceptionWithResponse, RestClient::Exception,
             SocketError, Errno::ECONNREFUSED, Errno::ETIMEDOUT,
             Errno::EHOSTUNREACH, JSON::ParserError, StandardError => e
        Rails.logger.warn(
          "DiscordNotifier failed: #{e.class} #{e.message} " \
          "(run=#{run&.id} method=#{method_name})"
        )
        nil
      end

      # Mirrors DiscordApi's "Bot <token>" prefix. Returns nil when
      # credentials are absent (test env, fresh checkout) — `send_message`
      # short-circuits on a blank token so the rescue chain never has to.
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
