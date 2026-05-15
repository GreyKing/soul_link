class GymPollLockJob < ApplicationJob
  queue_as :default

  def perform(poll_id)
    poll = GymPoll.find_by(id: poll_id)
    return unless poll&.locked?
    return unless poll.discord_message_id && poll.discord_channel_id

    token = Rails.application.credentials.discord[:token]

    embed_response = patch_embed(poll, token)
    Rails.logger.error "GymPollLockJob: PATCH failed #{embed_response.code}" unless embed_response.is_a?(Net::HTTPSuccess)

    return if poll.pinged_at.present?

    ping_response = post_ping(poll, token)
    if ping_response.is_a?(Net::HTTPSuccess)
      poll.update_column(:pinged_at, Time.current)
    else
      Rails.logger.error "GymPollLockJob: POST ping failed #{ping_response.code} #{ping_response.body}"
    end
  end

  private

  def patch_embed(poll, token)
    uri = URI("https://discord.com/api/v10/channels/#{poll.discord_channel_id}/messages/#{poll.discord_message_id}")
    request = Net::HTTP::Patch.new(uri)
    request["Authorization"] = "Bot #{token}"
    request["Content-Type"]  = "application/json"
    request.body = { embeds: [locked_embed(poll)], components: locked_components(poll) }.to_json
    https(uri).request(request)
  end

  def post_ping(poll, token)
    uri = URI("https://discord.com/api/v10/channels/#{poll.discord_channel_id}/messages")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bot #{token}"
    request["Content-Type"]  = "application/json"
    request.body = { content: ping_text(poll) }.to_json
    https(uri).request(request)
  end

  def https(uri)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http
  end

  def ping_text(poll)
    tz   = ActiveSupport::TimeZone[poll.soul_link_run.timezone]
    slot = poll.slots.find { |s| s["index"].to_i == poll.locked_slot_index }
    at   = Time.iso8601(slot["scheduled_at"]).in_time_zone(tz)
    when_str = at.strftime("%A, %B %-d at %-l:%M %p")
    mentions = SoulLink::GameState.players.map { |p| "<@#{p["discord_user_id"]}>" }.join(" ")
    "🎉 Gym poll locked: **#{when_str} #{tz.tzinfo.friendly_identifier} time**. #{mentions} — see you there!"
  end

  def locked_embed(poll)
    {
      title: "🔒 Gym Poll — LOCKED",
      description: ping_text(poll).sub(/^🎉 Gym poll locked: /, ""),
      color: 0x00ff00,
      timestamp: Time.now.iso8601
    }
  end

  def locked_components(poll)
    [
      {
        type: 1, components: [
          { type: 2, style: 4, label: "🔄 Reset", custom_id: "soul_link:gym_poll_reset:#{poll.id}" }
        ]
      }
    ]
  end
end
