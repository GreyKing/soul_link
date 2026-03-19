class GymScheduleDiscordUpdateJob < ApplicationJob
  queue_as :default

  def perform(schedule_id)
    schedule = GymSchedule.find(schedule_id)
    return unless schedule.discord_message_id && schedule.discord_channel_id

    token = Rails.application.credentials.discord[:token]

    embed = build_embed(schedule)
    components = build_components(schedule)

    uri = URI("https://discord.com/api/v10/channels/#{schedule.discord_channel_id}/messages/#{schedule.discord_message_id}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Patch.new(uri)
    request["Authorization"] = "Bot #{token}"
    request["Content-Type"] = "application/json"
    request.body = { embeds: [embed], components: components }.to_json

    response = http.request(request)
    Rails.logger.error "Discord embed update failed: #{response.code} #{response.body}" unless response.is_a?(Net::HTTPSuccess)
  end

  private

  def build_embed(schedule)
    rsvp_lines = schedule.players.map do |player|
      uid = player["discord_user_id"].to_s
      name = player["display_name"]
      response = schedule.rsvp_for(uid)
      emoji = case response
              when "yes" then "\u2705"
              when "no" then "\u274C"
              when "maybe" then "\u2753"
              else "\u23F3"
              end
      "#{emoji} **#{name}**: #{response&.capitalize || 'Pending'}"
    end

    status_text = case schedule.status
                  when "proposed" then "\uD83D\uDCCB Proposed"
                  when "confirmed" then "\u2705 Confirmed"
                  when "completed" then "\uD83C\uDFC6 Completed"
                  when "cancelled" then "\u274C Cancelled"
                  end

    {
      title: "\uD83D\uDCC5 Gym Day Schedule",
      description: "**When:** #{schedule.scheduled_at.strftime('%A, %B %d at %I:%M %p')}\n" \
        "**Proposed by:** #{schedule.proposer_name}\n" \
        "**Status:** #{status_text}\n\n" \
        "**RSVPs:**\n#{rsvp_lines.join("\n")}",
      color: schedule.all_accepted? ? 0x00ff00 : 0x5865F2,
      footer: { text: "Use the buttons below to RSVP" },
      timestamp: Time.now.iso8601
    }
  end

  def build_components(schedule)
    return [] if schedule.cancelled? || schedule.completed?

    [
      {
        type: 1,
        components: [
          { type: 2, style: 3, label: "Yes", custom_id: "soul_link:gym_rsvp:#{schedule.id}:yes" },
          { type: 2, style: 2, label: "Maybe", custom_id: "soul_link:gym_rsvp:#{schedule.id}:maybe" },
          { type: 2, style: 4, label: "No", custom_id: "soul_link:gym_rsvp:#{schedule.id}:no" }
        ]
      }
    ]
  end
end
