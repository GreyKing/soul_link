require "test_helper"

module SoulLink
  class ParseSaveDataJobTest < ActiveJob::TestCase
    setup do
      @run = create(:soul_link_run)
      @session = create(:soul_link_emulator_session, :ready, soul_link_run: @run)
      @slot = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1)
    end

    # --- success path -------------------------------------------------------

    test "writes parsed_* attrs via update_columns when parse returns a Result" do
      @slot.update!(save_data: "\x00".b * 0x80000)

      result = SoulLink::SaveParser::Result.new(
        trainer_name:   "Lyra",
        money:          12_345,
        play_seconds:   3_600,
        badges_count:   4,
        map_id:         42,
        trainer_id:     0xABCD,
        secret_id:      0x1357,
        pokedex_caught: 50,
        pokedex_seen:   75,
        hof_count:      0
      )

      SoulLink::SaveParser.stub(:parse, result) do
        SoulLink::ParseSaveDataJob.perform_now(@slot)
      end

      @slot.reload
      assert_equal "Lyra",  @slot.parsed_trainer_name
      assert_equal 12_345,  @slot.parsed_money
      assert_equal 3_600,   @slot.parsed_play_seconds
      assert_equal 4,       @slot.parsed_badges
      assert_equal 42,      @slot.parsed_map_id
      # Step 16 columns also populate.
      assert_equal 0xABCD,  @slot.parsed_trainer_id
      assert_equal 0x1357,  @slot.parsed_secret_id
      assert_equal 50,      @slot.parsed_pokedex_caught
      assert_equal 75,      @slot.parsed_pokedex_seen
      assert_equal 0,       @slot.parsed_hof_count
      assert_not_nil @slot.parsed_at
    end

    # --- failure path -------------------------------------------------------
    #
    # KG-13 (closed Step 15): parse failure now LEAVES every parsed_*
    # field at its prior value and only stamps `parsed_at`. This
    # prevents the previous behavior — zeroing parsed_badges on a
    # CRC-failed save — from producing spurious BadgeLost events when
    # the next valid save lands.

    test "KG-13: parse failure leaves parsed_badges and other parsed_* alone, only updates parsed_at" do
      @slot.update_columns(
        parsed_trainer_name: "PriorName",
        parsed_money:        9_999,
        parsed_play_seconds: 1_234,
        parsed_badges:       5,
        parsed_map_id:       42,
        parsed_at:           1.minute.ago
      )
      old_parsed_at = @slot.parsed_at
      @slot.update!(save_data: "\xFF".b * 0x80000)

      SoulLink::SaveParser.stub(:parse, nil) do
        SoulLink::ParseSaveDataJob.perform_now(@slot)
      end

      @slot.reload
      assert_equal "PriorName", @slot.parsed_trainer_name
      assert_equal 9_999,       @slot.parsed_money
      assert_equal 1_234,       @slot.parsed_play_seconds
      assert_equal 5,           @slot.parsed_badges
      assert_equal 42,          @slot.parsed_map_id
      assert @slot.parsed_at > old_parsed_at, "parsed_at should be refreshed even on failure"
    end

    test "KG-13: parse failure does not dispatch the diff (no spurious BadgeLost)" do
      @slot.update_columns(parsed_badges: 5, parsed_at: 1.minute.ago)
      @slot.update!(save_data: "\xFF".b * 0x80000)

      called = false
      SoulLink::SaveParser.stub(:parse, nil) do
        SoulLink::SaveDiffDispatcher.stub(:dispatch, ->(*_) { called = true }) do
          SoulLink::ParseSaveDataJob.perform_now(@slot)
        end
      end

      assert_not called, "SaveDiffDispatcher.dispatch must not be called when the parse fails"
    end

    # --- callback non-firing ------------------------------------------------
    #
    # The job MUST write through `update_columns` rather than `update!` —
    # otherwise the model's `after_update_commit :enqueue_parse_if_save_changed`
    # callback would fire on every parse-attrs write. The simplest
    # demonstration: the job's write does not enqueue another
    # ParseSaveDataJob.

    test "job does not enqueue another ParseSaveDataJob on completion" do
      @slot.update!(save_data: "\x00".b * 0x80000)

      result = SoulLink::SaveParser::Result.new(
        trainer_name: "X", money: 0, play_seconds: 0, badges_count: 0, map_id: nil
      )

      SoulLink::SaveParser.stub(:parse, result) do
        assert_no_enqueued_jobs(only: SoulLink::ParseSaveDataJob) do
          SoulLink::ParseSaveDataJob.perform_now(@slot)
        end
      end
    end

    # --- empty/nil save_data -----------------------------------------------

    test "no-op when slot has nil save_data" do
      assert_nil @slot.save_data

      called = false
      stub = ->(_bytes) { called = true; nil }
      SoulLink::SaveParser.stub(:parse, stub) do
        SoulLink::ParseSaveDataJob.perform_now(@slot)
      end

      assert_not called, "parser should not be invoked when save_data is nil"
      assert_nil @slot.reload.parsed_at
    end

    test "no-op when slot has empty save_data" do
      @slot.update!(save_data: "")

      called = false
      stub = ->(_bytes) { called = true; nil }
      SoulLink::SaveParser.stub(:parse, stub) do
        SoulLink::ParseSaveDataJob.perform_now(@slot)
      end

      assert_not called, "parser should not be invoked when save_data is blank"
    end

    test "no-op when slot is nil" do
      assert_nothing_raised { SoulLink::ParseSaveDataJob.perform_now(nil) }
    end

    # --- Step 15: SaveDiff dispatch -----------------------------------------

    test "first-ever parse (parsed_at was nil) does not dispatch the diff" do
      assert_nil @slot.parsed_at
      @slot.update!(save_data: "\x00".b * 0x80000)

      result = SoulLink::SaveParser::Result.new(
        trainer_name: "X", money: 0, play_seconds: 0, badges_count: 5, map_id: nil
      )

      called = false
      SoulLink::SaveParser.stub(:parse, result) do
        SoulLink::GymBeatenCoordinator.stub(:process, ->(*_) { called = true }) do
          SoulLink::ParseSaveDataJob.perform_now(@slot)
        end
      end

      assert_not called, "first-ever successful parse must NOT trigger the diff dispatch (baseline rule)"
      assert_equal 5, @slot.reload.parsed_badges
    end

    test "subsequent parse with badges unchanged does not auto-mark a gym" do
      @slot.update_columns(parsed_badges: 3, parsed_at: 1.minute.ago)
      @slot.update!(save_data: "\x00".b * 0x80000)

      result = SoulLink::SaveParser::Result.new(
        trainer_name: "X", money: 0, play_seconds: 0, badges_count: 3, map_id: nil
      )

      SoulLink::SaveParser.stub(:parse, result) do
        assert_no_difference "@run.gym_results.count" do
          SoulLink::ParseSaveDataJob.perform_now(@slot)
        end
      end
    end

    test "Step 16: dispatcher receives prev/curr snapshots after a successful parse" do
      @slot.update_columns(parsed_badges: 0, parsed_trainer_id: 0, parsed_secret_id: 0,
                           parsed_pokedex_caught: 0, parsed_pokedex_seen: 0, parsed_hof_count: 0,
                           parsed_at: 1.minute.ago)
      @slot.update!(save_data: "\x00".b * 0x80000)

      result = SoulLink::SaveParser::Result.new(
        trainer_name: "X", money: 0, play_seconds: 0, badges_count: 1, map_id: nil,
        trainer_id: 1234, secret_id: 5678,
        pokedex_caught: 50, pokedex_seen: 75, hof_count: 1
      )

      captured = nil
      capture_dispatch = ->(slot, prev:, curr:) { captured = { slot: slot, prev: prev, curr: curr } }

      SoulLink::SaveParser.stub(:parse, result) do
        SoulLink::SaveDiffDispatcher.stub(:dispatch, capture_dispatch) do
          SoulLink::ParseSaveDataJob.perform_now(@slot)
        end
      end

      assert_not_nil captured, "dispatcher should be invoked after a successful parse with prior baseline"
      assert_equal @slot.id, captured[:slot].id

      # prev: state before the parse-save write — all zeros, parsed_at present
      assert_not_nil captured[:prev][:parsed_at]
      assert_equal 0, captured[:prev][:badges]
      assert_equal 0, captured[:prev][:trainer_id]
      assert_equal 0, captured[:prev][:hof_count]

      # curr: state after the write — values from the SaveParser Result
      assert_equal 1,    captured[:curr][:badges]
      assert_equal 1234, captured[:curr][:trainer_id]
      assert_equal 5678, captured[:curr][:secret_id]
      assert_equal 50,   captured[:curr][:pokedex_caught]
      assert_equal 75,   captured[:curr][:pokedex_seen]
      assert_equal 1,    captured[:curr][:hof_count]
    end

    test "subsequent parse, badges +1, 4/4 satisfy → gym_results row created" do
      # Drop the setup-block session so this test owns exactly four sessions
      # on @run, matching the all-4 AND-gate the coordinator enforces.
      @session.destroy!
      sessions = 4.times.map do |i|
        create(:soul_link_emulator_session, :ready, soul_link_run: @run, active_save_slot: 1, discord_user_id: 200 + i)
      end
      slots = sessions.map do |s|
        create(:soul_link_emulator_save_slot, soul_link_emulator_session: s, slot_number: 1, parsed_badges: 0, parsed_at: 1.minute.ago)
      end

      # Bring all four to parsed_badges=1 BEFORE the job runs. The job's
      # parser stub returns badges_count=1, matching what the other slots
      # already show; the slot under test is the trigger that runs the diff.
      slots.each { |slot| slot.update_columns(parsed_badges: 1) }

      # Pick the first slot as the trigger; reset its parsed_badges to 0 +
      # an older parsed_at so the diff sees a 0 → 1 transition.
      trigger_slot = slots.first
      trigger_slot.update_columns(parsed_badges: 0, parsed_at: 5.minutes.ago)
      trigger_slot.update!(save_data: "\x00".b * 0x80000)

      result = SoulLink::SaveParser::Result.new(
        trainer_name: "X", money: 0, play_seconds: 0, badges_count: 1, map_id: nil
      )

      SoulLink::SaveParser.stub(:parse, result) do
        assert_difference "@run.gym_results.count", 1 do
          SoulLink::ParseSaveDataJob.perform_now(trigger_slot)
        end
      end

      assert @run.gym_results.exists?(gym_number: 1)
      assert_equal 1, @run.reload.gyms_defeated
    end

    test "integration: 4 player saves landing in sequence, 4th triggers the auto-mark" do
      @session.destroy!
      sessions = 4.times.map do |i|
        create(:soul_link_emulator_session, :ready, soul_link_run: @run, active_save_slot: 1, discord_user_id: 300 + i)
      end
      slots = sessions.map do |s|
        create(:soul_link_emulator_save_slot, soul_link_emulator_session: s, slot_number: 1, parsed_badges: 0, parsed_at: 5.minutes.ago)
      end

      result = SoulLink::SaveParser::Result.new(
        trainer_name: "X", money: 0, play_seconds: 0, badges_count: 1, map_id: nil
      )

      SoulLink::SaveParser.stub(:parse, result) do
        # Slot 1 → 1 player has badge → no auto-mark
        slots[0].update!(save_data: "\x00".b * 0x80000)
        SoulLink::ParseSaveDataJob.perform_now(slots[0])
        assert_equal 0, @run.gym_results.count, "after 1/4 there should be no auto-mark"

        # Slot 2 → 2 players → no auto-mark
        slots[1].update!(save_data: "\x00".b * 0x80000)
        SoulLink::ParseSaveDataJob.perform_now(slots[1])
        assert_equal 0, @run.gym_results.count, "after 2/4 there should be no auto-mark"

        # Slot 3 → 3 players → no auto-mark
        slots[2].update!(save_data: "\x00".b * 0x80000)
        SoulLink::ParseSaveDataJob.perform_now(slots[2])
        assert_equal 0, @run.gym_results.count, "after 3/4 there should be no auto-mark"

        # Slot 4 → 4 players → auto-mark fires for gym 1
        slots[3].update!(save_data: "\x00".b * 0x80000)
        SoulLink::ParseSaveDataJob.perform_now(slots[3])
      end

      assert_equal 1, @run.gym_results.count, "after 4/4 the auto-mark should fire exactly once"
      assert @run.gym_results.exists?(gym_number: 1)
      assert_equal 1, @run.reload.gyms_defeated
    end

    # --- retry safety -------------------------------------------------------
    #
    # Reviewer focus area #11: if the coordinator raises mid-dispatch, the
    # parse_save_data is already persisted via update_columns BEFORE the
    # dispatch line. ActiveJob retries the whole job. On retry,
    # `prev_badges` (now the just-written value) equals `curr_badges`, so
    # SaveDiff.between returns an empty Result and the coordinator is
    # never re-invoked. This test pins that invariant — without it, a
    # transient coordinator failure could double-fire the auto-mark on
    # retry.

    test "retry-safety: coordinator raise on first run does not double-fire on the retry" do
      @session.destroy!
      sessions = 4.times.map do |i|
        create(:soul_link_emulator_session, :ready, soul_link_run: @run, active_save_slot: 1, discord_user_id: 400 + i)
      end
      slots = sessions.map do |s|
        create(:soul_link_emulator_save_slot, soul_link_emulator_session: s, slot_number: 1, parsed_badges: 0, parsed_at: 5.minutes.ago)
      end
      # 3/4 already at badge=1 so the trigger slot's parse satisfies all-4
      slots[1..3].each { |slot| slot.update_columns(parsed_badges: 1) }

      trigger_slot = slots.first
      trigger_slot.update!(save_data: "\x00".b * 0x80000)

      result = SoulLink::SaveParser::Result.new(
        trainer_name: "X", money: 0, play_seconds: 0, badges_count: 1, map_id: nil
      )

      coordinator_calls = 0
      raising_then_passing = ->(_slot, _events) {
        coordinator_calls += 1
        raise StandardError, "coordinator boom" if coordinator_calls == 1
        # On retry: we should never reach this branch because the diff
        # is empty and the dispatch line short-circuits.
        flunk "coordinator must not be invoked on retry — diff should have been empty"
      }

      SoulLink::SaveParser.stub(:parse, result) do
        SoulLink::GymBeatenCoordinator.stub(:process, raising_then_passing) do
          # First attempt: parse writes parsed_badges=1, then coordinator raises
          assert_raises(StandardError) do
            SoulLink::ParseSaveDataJob.perform_now(trigger_slot)
          end
          assert_equal 1, trigger_slot.reload.parsed_badges,
            "parse_save_data must persist BEFORE the dispatch so retry sees prev==curr"
          assert_equal 0, @run.gym_results.count,
            "no auto-mark yet — coordinator raised before reaching create!"

          # Retry: prev_badges (1) == curr_badges (1), diff is empty,
          # coordinator is never re-invoked (the flunk above proves this).
          SoulLink::ParseSaveDataJob.perform_now(trigger_slot)
        end
      end

      assert_equal 1, coordinator_calls, "coordinator must be invoked exactly once across both job runs"
      assert_equal 0, @run.gym_results.count, "no spurious double-fire from retry"
    end

    # --- idempotency --------------------------------------------------------

    # --- Step 16: HoF integration ------------------------------------------
    #
    # Stubs SaveParser.parse to return progressively HoF-entered results
    # across 4 sessions. Only the 4th save sets run.completed_at — the
    # all-4 AND-gate enforces that the run isn't marked complete until
    # every player has reached the Hall of Fame.

    test "Step 16 integration: HoF auto-completion fires only on the 4th player's save" do
      @session.destroy!
      sessions = 4.times.map do |i|
        create(:soul_link_emulator_session, :ready, soul_link_run: @run, active_save_slot: 1, discord_user_id: 500 + i)
      end
      slots = sessions.map do |s|
        create(:soul_link_emulator_save_slot,
               soul_link_emulator_session: s, slot_number: 1,
               parsed_badges: 0, parsed_hof_count: 0, parsed_at: 5.minutes.ago)
      end

      result_with_hof = SoulLink::SaveParser::Result.new(
        trainer_name: "X", money: 0, play_seconds: 0, badges_count: 0, map_id: nil,
        trainer_id: 1, secret_id: 1, pokedex_caught: 0, pokedex_seen: 0, hof_count: 1
      )

      SoulLink::SaveParser.stub(:parse, result_with_hof) do
        slots[0].update!(save_data: "\x00".b * 0x80000)
        SoulLink::ParseSaveDataJob.perform_now(slots[0])
        assert_nil @run.reload.completed_at, "after 1/4 the run should NOT be complete"

        slots[1].update!(save_data: "\x00".b * 0x80000)
        SoulLink::ParseSaveDataJob.perform_now(slots[1])
        assert_nil @run.reload.completed_at, "after 2/4 the run should NOT be complete"

        slots[2].update!(save_data: "\x00".b * 0x80000)
        SoulLink::ParseSaveDataJob.perform_now(slots[2])
        assert_nil @run.reload.completed_at, "after 3/4 the run should NOT be complete"

        slots[3].update!(save_data: "\x00".b * 0x80000)
        SoulLink::ParseSaveDataJob.perform_now(slots[3])
        assert_not_nil @run.reload.completed_at, "after 4/4 the run SHOULD be complete"
      end
    end

    test "running the job twice produces the same final state" do
      @slot.update!(save_data: "\x00".b * 0x80000)

      result = SoulLink::SaveParser::Result.new(
        trainer_name: "Lyra",
        money:        12_345,
        play_seconds: 3_600,
        badges_count: 4,
        map_id:       42
      )

      SoulLink::SaveParser.stub(:parse, result) do
        SoulLink::ParseSaveDataJob.perform_now(@slot)
        first_state = @slot.reload.attributes.slice(
          "parsed_trainer_name", "parsed_money", "parsed_play_seconds",
          "parsed_badges", "parsed_map_id"
        )

        SoulLink::ParseSaveDataJob.perform_now(@slot)
        second_state = @slot.reload.attributes.slice(
          "parsed_trainer_name", "parsed_money", "parsed_play_seconds",
          "parsed_badges", "parsed_map_id"
        )

        assert_equal first_state, second_state,
          "second run should produce the same parsed_* values"
      end
    end
  end
end
