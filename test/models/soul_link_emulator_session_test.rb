require "test_helper"

class SoulLinkEmulatorSessionTest < ActiveSupport::TestCase
  # `assert_no_enqueued_jobs` comes from this helper. The parse-on-save
  # callback used to live here but moved to SoulLinkEmulatorSaveSlot when
  # save_data was migrated off this model in the Save Slots step.
  include ActiveJob::TestHelper

  # Named Discord user IDs used as claim targets. Keep them as recognizable
  # constants so the test reads naturally.
  GREY = "153665622641737728"
  ARATYPUSS = 600802903967531093
  SCYTHE = "189518174125817856"
  ZEALOUS = "182742127061630976"

  setup do
    @run = create(:soul_link_run)
    @unclaimed = create(:soul_link_emulator_session, :ready, soul_link_run: @run)
    @claimed = create(:soul_link_emulator_session, :ready, :claimed, soul_link_run: @run)
    @generating = create(:soul_link_emulator_session, :generating, soul_link_run: @run)
  end

  # --- validations ---------------------------------------------------------

  test "valid statuses are accepted" do
    SoulLinkEmulatorSession::STATUSES.each do |s|
      session = SoulLinkEmulatorSession.new(soul_link_run: @run, status: s, seed: "x")
      assert session.valid?, "expected status=#{s.inspect} to be valid: #{session.errors.full_messages}"
    end
  end

  test "invalid status fails validation" do
    session = SoulLinkEmulatorSession.new(soul_link_run: @run, status: "bogus", seed: "x")
    assert_not session.valid?
    assert_includes session.errors[:status], "is not included in the list"
  end

  test "seed is required" do
    session = SoulLinkEmulatorSession.new(soul_link_run: @run, status: "pending", seed: nil)
    assert_not session.valid?
    assert_includes session.errors[:seed], "can't be blank"
  end

  test "two unclaimed sessions in the same run are valid (NULL ignored by unique index)" do
    other = create(:soul_link_emulator_session, :ready, soul_link_run: @run)
    assert_nil @unclaimed.discord_user_id
    assert_nil other.discord_user_id
    assert_equal @unclaimed.soul_link_run_id, other.soul_link_run_id

    extra = SoulLinkEmulatorSession.new(
      soul_link_run: @run,
      status: "pending",
      seed: "another-unclaimed"
    )
    assert extra.valid?
    assert extra.save
  end

  test "two claimed sessions for same (run, discord_user_id) are invalid" do
    duplicate = SoulLinkEmulatorSession.new(
      soul_link_run: @claimed.soul_link_run,
      discord_user_id: @claimed.discord_user_id,
      status: "ready",
      seed: "dup-seed"
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:discord_user_id], "has already been taken"
  end

  # --- scopes --------------------------------------------------------------

  test "ready scope returns only sessions with status ready" do
    ready = SoulLinkEmulatorSession.ready
    assert_includes ready, @unclaimed
    assert_includes ready, @claimed
    assert_not_includes ready, @generating
    ready.each { |s| assert_equal "ready", s.status }
  end

  test "unclaimed scope returns only sessions without discord_user_id" do
    unclaimed = SoulLinkEmulatorSession.unclaimed
    assert_includes unclaimed, @unclaimed
    assert_not_includes unclaimed, @claimed
    unclaimed.each { |s| assert_nil s.discord_user_id }
  end

  test "claimed scope returns only sessions with discord_user_id" do
    claimed = SoulLinkEmulatorSession.claimed
    assert_includes claimed, @claimed
    assert_not_includes claimed, @unclaimed
    claimed.each { |s| assert_not_nil s.discord_user_id }
  end

  # --- claim! happy path & error path -------------------------------------

  test "claim! sets discord_user_id and returns the reloaded record" do
    result = @unclaimed.claim!(ARATYPUSS)
    assert_equal ARATYPUSS, @unclaimed.discord_user_id
    assert_equal ARATYPUSS, result.discord_user_id
    # reload returns self, so the same object is returned
    assert_same @unclaimed, result
  end

  test "claim! raises AlreadyClaimedError when row already has a discord_user_id" do
    assert_raises(SoulLinkEmulatorSession::AlreadyClaimedError) do
      @claimed.claim!(ARATYPUSS)
    end
  end

  # --- race safety ---------------------------------------------------------

  # The contract is: `claim!` must be safe when two callers race for the same
  # unclaimed row. This is implemented via an UPDATE ... WHERE discord_user_id
  # IS NULL — the database, not Ruby, decides who wins. Simulate that by
  # holding a stale in-memory copy whose row has been claimed by someone else
  # in the meantime, and asserting that the stale claim is rejected at the SQL
  # guard rather than slipping through.
  test "claim! is race-safe: stale in-memory record cannot overwrite a fresh claim" do
    fresh_copy = SoulLinkEmulatorSession.find(@unclaimed.id)
    stale_copy = SoulLinkEmulatorSession.find(@unclaimed.id)

    # Caller A wins the race at the SQL level.
    fresh_copy.claim!(ARATYPUSS)
    assert_equal ARATYPUSS, fresh_copy.discord_user_id

    # Caller B's stale in-memory copy still believes the row is unclaimed —
    # if `claim!` checked Ruby state instead of the SQL guard, this would
    # silently succeed and clobber ARATYPUSS's claim.
    assert_nil stale_copy.discord_user_id
    assert_raises(SoulLinkEmulatorSession::AlreadyClaimedError) do
      stale_copy.claim!(SCYTHE)
    end

    # Reload from DB to confirm the original claim is still intact.
    assert_equal ARATYPUSS, SoulLinkEmulatorSession.find(@unclaimed.id).discord_user_id
  end

  test "claim! affects exactly one row and only the matching id" do
    other_unclaimed = create(:soul_link_emulator_session, :ready, soul_link_run: @run)
    @unclaimed.claim!(ZEALOUS)
    # Sibling unclaimed in the same run is untouched.
    assert_nil other_unclaimed.reload.discord_user_id
  end

  # --- predicates ----------------------------------------------------------

  test "ready? reflects status" do
    assert @unclaimed.ready?
    assert_not @generating.ready?
  end

  test "claimed? reflects presence of discord_user_id" do
    assert_not @unclaimed.claimed?
    assert @claimed.claimed?
  end

  # --- rom_full_path -------------------------------------------------------

  test "rom_full_path returns a Pathname under Rails.root when rom_path is set" do
    path = @unclaimed.rom_full_path
    assert_instance_of Pathname, path
    assert path.to_s.start_with?(Rails.root.to_s)
    assert path.to_s.end_with?(@unclaimed.rom_path)
  end

  test "rom_full_path returns nil when rom_path is blank" do
    assert_nil @generating.rom_full_path

    @unclaimed.rom_path = ""
    assert_nil @unclaimed.rom_full_path
  end

  # --- cheats --------------------------------------------------------------
  #
  # `#cheats` reads `SoulLink::GameState.cheats` and pulls the
  # `action_replay` array. Stub the GameState class method per case so the
  # tests don't depend on the on-disk YAML.

  test "cheats returns [] when GameState has no cheats configured" do
    SoulLink::GameState.stub(:cheats, {}) do
      assert_equal [], @unclaimed.cheats
    end
  end

  test "cheats returns [] when GameState has no action_replay key" do
    SoulLink::GameState.stub(:cheats, { "something_else" => [] }) do
      assert_equal [], @unclaimed.cheats
    end
  end

  test "cheats returns [] when action_replay is not an Array (e.g. nil)" do
    SoulLink::GameState.stub(:cheats, { "action_replay" => nil }) do
      assert_equal [], @unclaimed.cheats
    end
  end

  test "cheats returns the action_replay array when present" do
    payload = [
      { "name" => "Walk Through Walls", "enabled" => true, "code" => "02000000 12345678" },
      { "name" => "Shiny Encounter",    "enabled" => false, "code" => "94000130 FCFF0000" }
    ]
    SoulLink::GameState.stub(:cheats, { "action_replay" => payload }) do
      assert_equal payload, @unclaimed.cheats
    end
  end

  # --- after_destroy :delete_rom_file --------------------------------------
  #
  # The callback removes the on-disk ROM when the row is destroyed (it's how
  # the regenerate channel action reclaims disk via `destroy_all`). It must
  # be defensive against missing files and nil rom_path — both happen in
  # practice (cleanup rake task already nilled the path; or manual cleanup).

  test "after_destroy deletes the on-disk rom file" do
    tmp_dir = Rails.root.join("tmp", "test_emu_session_destroy")
    FileUtils.mkdir_p(tmp_dir)
    file = Tempfile.create([ "rom", ".nds" ], tmp_dir)
    file.close
    rel_path = Pathname.new(file.path).relative_path_from(Rails.root).to_s

    session = create(:soul_link_emulator_session, soul_link_run: @run, rom_path: rel_path)
    assert File.exist?(file.path), "precondition: tempfile should exist"

    session.destroy

    assert_not File.exist?(file.path), "after_destroy should remove the rom file"
  ensure
    File.delete(file.path) if file && File.exist?(file.path)
    FileUtils.rm_rf(tmp_dir) if tmp_dir
  end

  test "after_destroy is safe when rom file is missing" do
    rel_path = "tmp/test_emu_session_missing/never_existed.nds"
    session = create(:soul_link_emulator_session, soul_link_run: @run, rom_path: rel_path)
    assert_not File.exist?(Rails.root.join(rel_path)), "precondition: file must not exist"

    assert_nothing_raised { session.destroy }
  end

  test "after_destroy is safe when rom_path is nil" do
    session = create(:soul_link_emulator_session, soul_link_run: @run, rom_path: nil)
    assert_nil session.rom_full_path

    assert_nothing_raised { session.destroy }
  end

  # The widened rescue catches *any* StandardError from the underlying delete
  # (EACCES from a permission-locked dir, EBUSY from a locked file, an NFS
  # timeout, etc.) so a transient disk problem can never roll back the AR
  # delete and leave the cascade in a half-deleted state.
  test "after_destroy survives a Pathname#delete raising EACCES and logs it" do
    tmp_dir = Rails.root.join("tmp", "test_emu_session_eacces")
    FileUtils.mkdir_p(tmp_dir)
    file = Tempfile.create([ "rom", ".nds" ], tmp_dir)
    file.close
    rel_path = Pathname.new(file.path).relative_path_from(Rails.root).to_s

    session = create(:soul_link_emulator_session, soul_link_run: @run, rom_path: rel_path)
    session_id = session.id

    log_buffer = StringIO.new
    captured_logger = Logger.new(log_buffer)

    Pathname.stub_any_instance(:delete, ->(*) { raise Errno::EACCES, "Permission denied" }) do
      Rails.stub(:logger, captured_logger) do
        assert_nothing_raised { session.destroy }
      end
    end

    # Row is gone — disk failure must not have rolled back the destroy.
    assert_nil SoulLinkEmulatorSession.find_by(id: session_id),
      "row should be destroyed even when on-disk delete raises"
    # Failure was logged (we don't assert exact wording, just that we logged).
    assert_match(/delete_rom_file/, log_buffer.string)
    assert_match(/EACCES/i, log_buffer.string)
  ensure
    File.delete(file.path) if file && File.exist?(file.path)
    FileUtils.rm_rf(tmp_dir) if tmp_dir
  end

  # --- save_slots association + active_slot --------------------------------
  #
  # save_data + parsed_* moved off the session in the Save Slots step. The
  # session now has up to 5 SoulLinkEmulatorSaveSlot rows (1..5) and a
  # nullable `active_save_slot` pointer that resolves to one of them.

  test "has_many :save_slots returns the session's slots" do
    s1 = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @claimed, slot_number: 1)
    s2 = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @claimed, slot_number: 2)
    other = create(:soul_link_emulator_save_slot, soul_link_emulator_session: @unclaimed, slot_number: 1)

    assert_includes @claimed.save_slots, s1
    assert_includes @claimed.save_slots, s2
    assert_not_includes @claimed.save_slots, other
  end

  test "destroying a session destroys its save_slots (dependent: :destroy)" do
    slot = create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @claimed, slot_number: 1)
    @claimed.destroy
    assert_nil SoulLinkEmulatorSaveSlot.find_by(id: slot.id)
  end

  test "active_slot returns the save_slot whose slot_number matches active_save_slot" do
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @claimed, slot_number: 1)
    s2 = create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @claimed, slot_number: 2)
    @claimed.update!(active_save_slot: 2)
    assert_equal s2, @claimed.active_slot
  end

  test "active_slot returns nil when active_save_slot is nil" do
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @claimed, slot_number: 1)
    @claimed.update!(active_save_slot: nil)
    assert_nil @claimed.active_slot
  end

  test "active_slot returns nil when active_save_slot points at a non-existent slot_number" do
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @claimed, slot_number: 1)
    @claimed.update!(active_save_slot: 4)
    assert_nil @claimed.active_slot
  end
end

# Tiny helper: minitest doesn't ship `stub_any_instance` for `Pathname#delete`.
# Reopen `Pathname` to provide it for the EACCES test above. Scoped here to
# this test file so production code is unaffected.
class Pathname
  def self.stub_any_instance(method, replacement)
    original = instance_method(method)
    define_method(method) { |*args, &block| replacement.call(self, *args, &block) }
    yield
  ensure
    define_method(method, original)
  end
end
