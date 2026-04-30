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
        trainer_name: "Lyra",
        money:        12_345,
        play_seconds: 3_600,
        badges_count: 4,
        map_id:       42
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
      assert_not_nil @slot.parsed_at
    end

    # --- failure path -------------------------------------------------------

    test "writes nil-attrs and parsed_at when parser returns nil" do
      @slot.update!(save_data: "\xFF".b * 0x80000)

      SoulLink::SaveParser.stub(:parse, nil) do
        SoulLink::ParseSaveDataJob.perform_now(@slot)
      end

      @slot.reload
      assert_nil @slot.parsed_trainer_name
      assert_nil @slot.parsed_money
      assert_nil @slot.parsed_play_seconds
      assert_equal 0, @slot.parsed_badges
      assert_nil @slot.parsed_map_id
      assert_not_nil @slot.parsed_at, "parsed_at must be set even on failure to prevent re-parse loops"
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

    # --- idempotency --------------------------------------------------------

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
