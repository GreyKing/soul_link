require "test_helper"

module SoulLink
  class GenerateRunRomsJobTest < ActiveJob::TestCase
    setup do
      @run = create(:soul_link_run)
    end

    # Replace `RomRandomizer#call` with the supplied lambda for the duration
    # of the block, then restore the original. The lambda is invoked in the
    # service's instance scope, so it has direct access to `@session`.
    #
    # Returns a counter struct so tests can assert on invocation count and
    # the sessions seen, without coupling to the production code's internals.
    def with_randomizer_stub(behavior)
      counter = Struct.new(:calls, :sessions).new(0, [])
      original = SoulLink::RomRandomizer.instance_method(:call)

      SoulLink::RomRandomizer.define_method(:call) do
        counter.calls    += 1
        counter.sessions << @session
        instance_exec(@session, counter, &behavior)
      end

      yield counter
    ensure
      SoulLink::RomRandomizer.define_method(:call, original) if original
    end

    # Default behavior helper: succeed silently — useful when the test only
    # cares about the orchestration shape, not what the service did.
    def succeed_quietly
      ->(_session, _counter) { true }
    end

    # ---- happy path --------------------------------------------------------

    test "creates 4 unclaimed pending sessions when run has none" do
      with_randomizer_stub(succeed_quietly) do |counter|
        SoulLink::GenerateRunRomsJob.perform_now(@run)
        assert_equal 4, counter.calls, "RomRandomizer should be invoked exactly 4 times"
      end

      sessions = SoulLinkEmulatorSession.where(soul_link_run_id: @run.id)
      assert_equal 4, sessions.count
      assert_equal 4, sessions.map(&:seed).uniq.size, "all 4 seeds should be unique"

      sessions.each do |s|
        assert_nil s.discord_user_id, "new sessions must be unclaimed"
        # Seed format: positive 63-bit integer as a string.
        assert_match(/\A\d+\z/, s.seed)
        assert s.seed.to_i.positive?
        assert s.seed.to_i < 2**63
      end
    end

    # ---- idempotency -------------------------------------------------------

    test "is a no-op when 4 sessions already exist for the run" do
      4.times do |i|
        create(:soul_link_emulator_session, soul_link_run: @run, status: "ready", seed: "preexisting-#{i}")
      end

      with_randomizer_stub(succeed_quietly) do |counter|
        assert_no_difference "SoulLinkEmulatorSession.where(soul_link_run_id: #{@run.id}).count" do
          SoulLink::GenerateRunRomsJob.perform_now(@run)
        end
        assert_equal 0, counter.calls, "no service call should fire when sessions already exist"
      end
    end

    test "is a no-op when more than 4 sessions exist (defensive)" do
      5.times do |i|
        create(:soul_link_emulator_session, soul_link_run: @run, status: "ready", seed: "preexisting-#{i}")
      end

      with_randomizer_stub(succeed_quietly) do |counter|
        SoulLink::GenerateRunRomsJob.perform_now(@run)
        assert_equal 0, counter.calls
      end

      assert_equal 5, SoulLinkEmulatorSession.where(soul_link_run_id: @run.id).count
    end

    # ---- partial failure tolerance ----------------------------------------

    test "handled per-session failure does not halt remaining ROM generation" do
      # Fail the second invocation only; the others succeed via the same
      # mutation pattern the real service uses.
      behavior = lambda do |session, counter|
        if counter.calls == 2
          session.update!(status: "failed", error_message: "synthetic boom")
          false
        else
          session.update!(
            status: "ready",
            rom_path: "storage/roms/randomized/run_#{session.soul_link_run_id}/session_#{session.id}.nds"
          )
          true
        end
      end

      with_randomizer_stub(behavior) do |counter|
        SoulLink::GenerateRunRomsJob.perform_now(@run)
        assert_equal 4, counter.calls, "all 4 sessions should still be attempted"
      end

      sessions = SoulLinkEmulatorSession.where(soul_link_run_id: @run.id).order(:id)
      assert_equal 4, sessions.count
      assert_equal 3, sessions.where(status: "ready").count
      assert_equal 1, sessions.where(status: "failed").count
      assert_equal "synthetic boom", sessions.where(status: "failed").first.error_message
    end

    # An UNHANDLED exception inside the service must also not abort the loop —
    # the job rescues StandardError and continues.
    test "unrescued StandardError in one session does not stop the others" do
      behavior = lambda do |session, counter|
        raise "synthetic crash" if counter.calls == 2
        session.update!(status: "ready", rom_path: "storage/roms/randomized/x.nds")
        true
      end

      with_randomizer_stub(behavior) do |counter|
        # Job should swallow the StandardError silently from the caller's POV.
        assert_nothing_raised do
          SoulLink::GenerateRunRomsJob.perform_now(@run)
        end
        assert_equal 4, counter.calls
      end

      sessions = SoulLinkEmulatorSession.where(soul_link_run_id: @run.id)
      assert_equal 4, sessions.count
      # 3 sessions reached the success branch; the crash victim was left as `pending`.
      assert_equal 3, sessions.where(status: "ready").count
      assert_equal 1, sessions.where(status: "pending").count
    end
  end
end
