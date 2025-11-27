# app/services/soul_link/events.rb
module SoulLink
  class Events
    class << self
      def record_catch(user_id:, name:, location:)
        Rails.logger.info("[SoulLink] Catch: user=#{user_id} name=#{name} location=#{location}")
        # TODO: Persist to DB or YAML or wherever you want
      end

      def record_death(user_id:, name:, location:)
        Rails.logger.info("[SoulLink] Death: user=#{user_id} name=#{name} location=#{location}")
        # TODO: Persist
      end
    end
  end
end