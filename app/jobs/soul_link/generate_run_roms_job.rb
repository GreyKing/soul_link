module SoulLink
  # Batch-creates the 4 emulator sessions for a Soul Link run and generates
  # a randomized ROM for each. One session per player slot — claiming is the
  # users' problem (see SoulLinkEmulatorSession#claim!).
  #
  # Idempotent on count: re-enqueueing for a run that already has 4 sessions
  # is a safe no-op. Individual ROM failures do NOT halt the rest — each
  # session reflects its own outcome via status / error_message.
  class GenerateRunRomsJob < ApplicationJob
    queue_as :default

    SESSIONS_PER_RUN = 4

    def perform(soul_link_run)
      return if SoulLinkEmulatorSession.where(soul_link_run_id: soul_link_run.id).count >= SESSIONS_PER_RUN

      sessions = create_sessions(soul_link_run)

      # Subprocesses run OUTSIDE the transaction. Holding a row-level lock
      # while shelling out to Java would needlessly serialize the four jobs
      # against any other writer touching the run.
      sessions.each do |session|
        SoulLink::RomRandomizer.new(session).call
      rescue StandardError => e
        # Belt-and-braces: the service itself swallows handled failures and
        # returns false. This rescue exists so a real bug in one ROM does
        # not abort generation of the others.
        Rails.logger.error("[GenerateRunRomsJob] session #{session.id} crashed: #{e.class}: #{e.message}")
      end
    end

    private

    def create_sessions(soul_link_run)
      SoulLinkEmulatorSession.transaction do
        Array.new(SESSIONS_PER_RUN) do
          SoulLinkEmulatorSession.create!(
            soul_link_run: soul_link_run,
            status: "pending",
            seed: random_seed,
            discord_user_id: nil
          )
        end
      end
    end

    # Positive 63-bit integer — fits Java `long`, avoids signed-overflow
    # surprises when the seed crosses the JNI boundary.
    def random_seed
      SecureRandom.random_number(2**63).to_s
    end
  end
end
