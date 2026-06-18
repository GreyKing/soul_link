class GymPollDiscordSyncJob < ApplicationJob
  queue_as :default

  def perform(poll_id)
    poll = GymPoll.find_by(id: poll_id)
    return unless poll
    return unless poll.discord_message_id && poll.discord_channel_id

    token = Rails.application.credentials.discord[:token]
    embed = SoulLink::GymPollMessage.embed(poll).merge(timestamp: Time.now.iso8601)
    components = SoulLink::GymPollMessage.components(poll)

    uri = URI("https://discord.com/api/v10/channels/#{poll.discord_channel_id}/messages/#{poll.discord_message_id}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Patch.new(uri)
    request["Authorization"] = "Bot #{token}"
    request["Content-Type"]  = "application/json"
    request.body = { embeds: [ embed ], components: components }.to_json

    response = http.request(request)
    return if response.is_a?(Net::HTTPSuccess)
    Rails.logger.error "GymPollDiscordSyncJob: PATCH failed #{response.code} #{response.body}"
  end
end
