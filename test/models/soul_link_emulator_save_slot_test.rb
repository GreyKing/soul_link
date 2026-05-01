require "test_helper"
require "turbo/broadcastable/test_helper"

class SoulLinkEmulatorSaveSlotTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include Turbo::Broadcastable::TestHelper

  setup do
    @run = create(:soul_link_run)
    @session = create(:soul_link_emulator_session, :ready, soul_link_run: @run)
  end

  # --- validations ---------------------------------------------------------

  test "slot_number is required" do
    slot = SoulLinkEmulatorSaveSlot.new(soul_link_emulator_session: @session, slot_number: nil)
    assert_not slot.valid?
    assert_includes slot.errors[:slot_number], "can't be blank"
  end

  test "slot_number must be within MIN_SLOT..MAX_SLOT" do
    [ 0, 6, -1, 100 ].each do |bad|
      slot = SoulLinkEmulatorSaveSlot.new(soul_link_emulator_session: @session, slot_number: bad)
      assert_not slot.valid?, "expected slot_number=#{bad} to be invalid"
      assert_includes slot.errors[:slot_number], "is not included in the list"
    end
  end

  test "slot_number 1..5 are valid" do
    (SoulLinkEmulatorSaveSlot::MIN_SLOT..SoulLinkEmulatorSaveSlot::MAX_SLOT).each do |n|
      session = create(:soul_link_emulator_session, :ready, soul_link_run: @run)
      slot = SoulLinkEmulatorSaveSlot.new(soul_link_emulator_session: session, slot_number: n)
      assert slot.valid?, "expected slot_number=#{n} to be valid"
    end
  end

  test "slot_number is unique within a session" do
    create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1)
    duplicate = SoulLinkEmulatorSaveSlot.new(soul_link_emulator_session: @session, slot_number: 1)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slot_number], "has already been taken"
  end

  test "the same slot_number is allowed across different sessions" do
    other_session = create(:soul_link_emulator_session, :ready, soul_link_run: @run)
    create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1)
    sibling = SoulLinkEmulatorSaveSlot.new(soul_link_emulator_session: other_session, slot_number: 1)
    assert sibling.valid?
  end

  # --- save_data gzip coder -----------------------------------------------
  #
  # Pokemon Platinum SRAM is ~512KB raw and mostly zero-padded; we gzip on
  # write and gunzip on read so the on-disk MEDIUMBLOB stays small. The
  # coder must round-trip exact bytes (binary equality) and handle nil and
  # empty values cleanly so factory defaults and fresh slots don't blow
  # up on save.

  test "save_data round-trips a 200KB random byte string exactly" do
    payload = SecureRandom.random_bytes(200_000)
    slot = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1, save_data: payload)

    reloaded = SoulLinkEmulatorSaveSlot.find(slot.id)
    assert_equal payload.bytesize, reloaded.save_data.bytesize
    assert_equal payload, reloaded.save_data.b,
      "decompressed bytes must equal original input"
  end

  test "save_data is stored compressed on disk (smaller than raw input)" do
    payload = ("\x00".b * 500_000) + SecureRandom.random_bytes(12_000)
    slot = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1, save_data: payload)

    raw_on_disk = slot.attributes_before_type_cast["save_data"]
    raw_bytes = raw_on_disk.is_a?(String) ? raw_on_disk : raw_on_disk.to_s
    assert raw_bytes.bytesize < payload.bytesize,
      "expected gzipped on-disk bytes (#{raw_bytes.bytesize}) to be smaller than raw input (#{payload.bytesize})"
    assert raw_bytes.bytesize < (payload.bytesize / 2),
      "expected at least 50% compression on highly-redundant SRAM-like payload"
    assert raw_bytes.b.start_with?("\x1f\x8b".b),
      "on-disk bytes should start with gzip magic header"
  end

  test "save_data nil round-trips as nil" do
    slot = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1, save_data: nil)
    reloaded = SoulLinkEmulatorSaveSlot.find(slot.id)
    assert_nil reloaded.save_data
  end

  test "save_data empty string round-trips as empty (no gzip overhead written)" do
    slot = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1, save_data: "")
    reloaded = SoulLinkEmulatorSaveSlot.find(slot.id)
    assert_equal "", reloaded.save_data.to_s
    raw = reloaded.attributes_before_type_cast["save_data"]
    raw_bytes = raw.is_a?(String) ? raw : raw.to_s
    assert raw_bytes.bytesize == 0 || !raw_bytes.b.start_with?("\x1f\x8b".b),
      "empty input should not produce a gzip header on disk"
  end

  test "save_data load passes through plaintext bytes lacking gzip magic" do
    plaintext = "LEGACY_PLAINTEXT_SAVE_BYTES_\x00\x01\x02".b
    slot = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1)
    slot.update_columns(save_data: plaintext)

    reloaded = SoulLinkEmulatorSaveSlot.find(slot.id)
    assert_equal plaintext, reloaded.save_data.b,
      "plaintext legacy values must pass through unchanged"
  end

  # --- after_*_commit :enqueue_parse_if_save_changed ----------------------
  #
  # Every slot create or save_data update should produce a parse job. Other
  # column updates (parsed_*) must NOT enqueue.

  test "creating a slot with non-nil save_data enqueues ParseSaveDataJob" do
    assert_enqueued_with(job: SoulLink::ParseSaveDataJob) do
      create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1,
                                            save_data: "\x00".b * 0x80000)
    end
  end

  test "creating a slot with nil save_data does NOT enqueue ParseSaveDataJob" do
    assert_no_enqueued_jobs(only: SoulLink::ParseSaveDataJob) do
      create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1, save_data: nil)
    end
  end

  test "updating save_data enqueues ParseSaveDataJob" do
    slot = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1)

    assert_enqueued_with(job: SoulLink::ParseSaveDataJob) do
      slot.update!(save_data: ("\x00".b * 0x80000))
    end
  end

  test "updating save_data to a different value enqueues ParseSaveDataJob" do
    slot = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1,
                                                  save_data: "\x00".b * 100)

    assert_enqueued_with(job: SoulLink::ParseSaveDataJob) do
      slot.update!(save_data: "\xFF".b * 100)
    end
  end

  test "updating other columns does NOT enqueue ParseSaveDataJob" do
    slot = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1,
                                                  save_data: "\x00".b * 100)

    assert_no_enqueued_jobs(only: SoulLink::ParseSaveDataJob) do
      slot.update!(parsed_trainer_name: "X")
    end
  end

  test "setting save_data to nil does NOT enqueue ParseSaveDataJob" do
    slot = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1,
                                                  save_data: "\x00".b * 100)

    assert_no_enqueued_jobs(only: SoulLink::ParseSaveDataJob) do
      slot.update!(save_data: nil)
    end
  end

  test "setting save_data to empty string does NOT enqueue ParseSaveDataJob" do
    slot = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1,
                                                  save_data: "\x00".b * 100)

    assert_no_enqueued_jobs(only: SoulLink::ParseSaveDataJob) do
      slot.update!(save_data: "")
    end
  end

  # update_columns bypasses the callback — this is what the parse job uses
  # to write parsed_* fields without re-triggering a parse.
  test "update_columns on parsed_* does NOT enqueue ParseSaveDataJob" do
    slot = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @session, slot_number: 1)

    assert_no_enqueued_jobs(only: SoulLink::ParseSaveDataJob) do
      slot.update_columns(parsed_trainer_name: "Lyra", parsed_at: Time.current)
    end
  end

  # --- KG-1: roster card broadcast ----------------------------------------
  #
  # The model fires a Turbo Stream replace on `[run, :emulator]` when a
  # parsed_* field changes (and on initial create). The broadcast renders
  # `emulator/_run_sidebar_card.html.erb` with `s: session` as the only
  # local — no current_user_id, no controller context. These tests guard
  # against that partial regressing into a state that requires more.

  test "create broadcasts a roster card replace to [run, :emulator]" do
    streams = capture_turbo_stream_broadcasts [ @run, :emulator ] do
      create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @session, slot_number: 1)
    end
    assert_equal 1, streams.size, "expected 1 turbo-stream; saw #{streams.size}: #{streams.map(&:to_s)}"
    assert_equal "replace", streams.first["action"]
    assert_equal "emulator_roster_session_#{@session.id}", streams.first["target"]
  end

  # `assert_turbo_stream_broadcasts` captures every broadcast on the
  # stream during the test (not just the block), so tests that need
  # baseline-vs-after counts use `capture_turbo_stream_broadcasts` to
  # snapshot before+after and diff explicitly.

  test "update to a parsed_* field broadcasts a roster card replace" do
    slot = create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @session, slot_number: 1)
    before = capture_turbo_stream_broadcasts([ @run, :emulator ]).size
    slot.update!(parsed_trainer_name: "Lyra")
    after = capture_turbo_stream_broadcasts([ @run, :emulator ]).size
    assert_equal 1, after - before, "expected 1 new broadcast; got #{after - before}"
  end

  test "update_columns on parsed_* does NOT broadcast (callbacks bypassed)" do
    slot = create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @session, slot_number: 1)
    before = capture_turbo_stream_broadcasts([ @run, :emulator ]).size
    slot.update_columns(parsed_trainer_name: "Updated", parsed_at: Time.current)
    after = capture_turbo_stream_broadcasts([ @run, :emulator ]).size
    assert_equal 0, after - before, "expected no new broadcasts; got #{after - before}"
  end

  test "update to a non-parsed field does NOT broadcast" do
    slot = create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @session, slot_number: 1)
    before = capture_turbo_stream_broadcasts([ @run, :emulator ]).size
    slot.touch
    after = capture_turbo_stream_broadcasts([ @run, :emulator ]).size
    assert_equal 0, after - before, "expected no new broadcasts; got #{after - before}"
  end

  test "run_sidebar_card partial renders standalone with only `s` local" do
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @session, slot_number: 1)
    @session.update_column(:active_save_slot, 1)
    rendered = ApplicationController.render(partial: "emulator/run_sidebar_card", locals: { s: @session.reload })
    assert_includes rendered, @session.seed
    # The YOU-marker Stimulus controller (Step 10) selects on this
    # attribute. Guard against the partial accidentally dropping it.
    assert_includes rendered, "data-discord-user-id="
  end
end
