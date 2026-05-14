class GymPollDiscordSyncJob < ApplicationJob
  queue_as :default

  def perform(poll_id)
    poll = GymPoll.find_by(id: poll_id)
    return unless poll
    return unless poll.discord_message_id && poll.discord_channel_id

    token = Rails.application.credentials.discord[:token]
    embed = build_embed(poll)
    components = build_components(poll)

    uri = URI("https://discord.com/api/v10/channels/#{poll.discord_channel_id}/messages/#{poll.discord_message_id}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Patch.new(uri)
    request["Authorization"] = "Bot #{token}"
    request["Content-Type"]  = "application/json"
    request.body = { embeds: [embed], components: components }.to_json

    response = http.request(request)
    return if response.is_a?(Net::HTTPSuccess)
    Rails.logger.error "GymPollDiscordSyncJob: PATCH failed #{response.code} #{response.body}"
  end

  private

  def build_embed(poll)
    state = poll.broadcast_state
    tz = ActiveSupport::TimeZone[state[:timezone]]
    week_label = state[:slots].first ? Time.iso8601(state[:slots].first[:scheduled_at]).in_time_zone(tz).strftime("Week of %b %-d") : ""

    slot_lines = state[:slots].map do |slot|
      at = Time.iso8601(slot[:scheduled_at]).in_time_zone(tz)
      label = at.strftime("%a %-l:%M %p")
      "**#{label}** — #{slot[:yes_count]}✅ / #{slot[:maybe_count]}❓ / #{slot[:no_count]}❌ / #{slot[:pending_count]}⏳"
    end

    {
      title: poll.locked? ? "🔒 Gym Poll — LOCKED" : "🗓️ Gym Poll — #{week_label}",
      description: slot_lines.join("\n"),
      color: poll.locked? ? 0x00ff00 : 0x5865F2,
      timestamp: Time.now.iso8601
    }
  end

  def build_components(poll)
    state = poll.broadcast_state
    tz = ActiveSupport::TimeZone[state[:timezone]]
    rows = []

    unless poll.locked?
      state[:slots].each do |slot|
        next if slot[:past]
        at = Time.iso8601(slot[:scheduled_at]).in_time_zone(tz)
        label_base = at.strftime("%-l%P").sub(":00", "")
        rows << {
          type: 1, components: [
            { type: 2, style: 3, label: "#{label_base} ✅", custom_id: "soul_link:gym_poll_vote:#{poll.id}:#{slot[:index]}:yes"   },
            { type: 2, style: 2, label: "#{label_base} ❓", custom_id: "soul_link:gym_poll_vote:#{poll.id}:#{slot[:index]}:maybe" },
            { type: 2, style: 4, label: "#{label_base} ❌", custom_id: "soul_link:gym_poll_vote:#{poll.id}:#{slot[:index]}:no"    }
          ]
        }
      end
    end

    rows << {
      type: 1, components: [
        { type: 2, style: 4, label: "🔄 Reset", custom_id: "soul_link:gym_poll_reset:#{poll.id}" }
      ]
    }
    rows
  end
end
