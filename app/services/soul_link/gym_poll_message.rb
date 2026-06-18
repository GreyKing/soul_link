module SoulLink
  # Builds the Discord message (embed + button rows) for a gym poll.
  # Single source of truth shared by the initial post (DiscordBot) and the
  # per-vote edit (GymPollDiscordSyncJob), so the two never drift.
  #
  # The embed lists who has responded with each choice — and crucially who is
  # still pending — by display name, instead of bare counts.
  class GymPollMessage
    # Response → emoji, in the order buckets render within a slot line.
    RESPONSE_EMOJI = { "yes" => "✅", "maybe" => "❓", "no" => "❌", "pending" => "⏳" }.freeze

    def self.embed(poll)      = new(poll).embed
    def self.components(poll) = new(poll).components

    def initialize(poll)
      @poll  = poll
      @state = poll.broadcast_state
      @tz    = ActiveSupport::TimeZone[@state[:timezone]]
    end

    # Returns the embed as a plain hash (title/description/color). Callers add
    # their own timestamp in the form their transport needs.
    def embed
      {
        title:       @poll.locked? ? "🔒 Gym Poll — LOCKED" : "🗓️ Gym Poll — #{week_label}",
        description: @state[:slots].map { |slot| slot_line(slot) }.join("\n\n"),
        color:       @poll.locked? ? 0x00ff00 : 0x5865F2
      }
    end

    # Returns Discord action rows: one yes/maybe/no row per upcoming slot
    # (omitted when locked), followed by the reset row.
    def components
      rows = []
      unless @poll.locked?
        @state[:slots].each { |slot| rows << vote_row(slot) unless slot[:past] }
      end
      rows << reset_row
      rows
    end

    private

    def week_label
      first = @state[:slots].first
      return "" unless first
      Time.iso8601(first[:scheduled_at]).in_time_zone(@tz).strftime("Week of %b %-d")
    end

    def slot_line(slot)
      at = Time.iso8601(slot[:scheduled_at]).in_time_zone(@tz)
      "**#{at.strftime('%a %-l:%M %p')}**\n#{voter_summary(slot)}"
    end

    # "✅ Alice, Bob · ❌ Carol · ⏳ Dave" — only buckets with members appear.
    def voter_summary(slot)
      slot_key = slot[:index].to_s
      grouped  = Hash.new { |h, k| h[k] = [] }
      @state[:players].each do |player|
        response = @state[:votes].dig(player["discord_user_id"].to_s, slot_key) || "pending"
        grouped[response] << player["display_name"]
      end

      RESPONSE_EMOJI.filter_map do |response, emoji|
        names = grouped[response]
        "#{emoji} #{names.join(', ')}" if names.any?
      end.join(" · ")
    end

    def vote_row(slot)
      label = Time.iso8601(slot[:scheduled_at]).in_time_zone(@tz).strftime("%a %-l%P").sub(":00", "")
      {
        type: 1, components: [
          { type: 2, style: 3, label: "#{label} ✅", custom_id: "soul_link:gym_poll_vote:#{@poll.id}:#{slot[:index]}:yes" },
          { type: 2, style: 2, label: "#{label} ❓", custom_id: "soul_link:gym_poll_vote:#{@poll.id}:#{slot[:index]}:maybe" },
          { type: 2, style: 4, label: "#{label} ❌", custom_id: "soul_link:gym_poll_vote:#{@poll.id}:#{slot[:index]}:no" }
        ]
      }
    end

    def reset_row
      { type: 1, components: [ { type: 2, style: 4, label: "🔄 Reset", custom_id: "soul_link:gym_poll_reset:#{@poll.id}" } ] }
    end
  end
end
