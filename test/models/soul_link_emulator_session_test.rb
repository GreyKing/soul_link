require "test_helper"

class SoulLinkEmulatorSessionTest < ActiveSupport::TestCase
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
  #
  # Tempfiles are created under `Rails.root.join("tmp")` so the relative
  # `rom_path` round-trips through the model's `Rails.root.join(rom_path)`
  # back to the real on-disk file. No writes to `storage/roms/`.

  test "after_destroy deletes the on-disk rom file" do
    tmp_dir = Rails.root.join("tmp", "test_emu_session_destroy")
    FileUtils.mkdir_p(tmp_dir)
    file = Tempfile.create(["rom", ".nds"], tmp_dir)
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
  # delete and leave the cascade in a half-deleted state. The original test
  # above covers ENOENT specifically; this one covers the broader contract.
  test "after_destroy survives a Pathname#delete raising EACCES and logs it" do
    tmp_dir = Rails.root.join("tmp", "test_emu_session_eacces")
    FileUtils.mkdir_p(tmp_dir)
    file = Tempfile.create(["rom", ".nds"], tmp_dir)
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

  # --- save_data gzip coder -----------------------------------------------
  #
  # Pokemon Platinum SRAM is ~512KB raw and mostly zero-padded; we gzip on
  # write and gunzip on read so the on-disk MEDIUMBLOB stays small. The
  # coder must round-trip exact bytes (binary equality) and handle nil and
  # empty values cleanly so factory defaults and fresh sessions don't blow
  # up on save.

  test "save_data round-trips a 200KB random byte string exactly" do
    payload = SecureRandom.random_bytes(200_000)
    session = create(:soul_link_emulator_session, soul_link_run: @run, save_data: payload)

    reloaded = SoulLinkEmulatorSession.find(session.id)
    assert_equal payload.bytesize, reloaded.save_data.bytesize
    assert_equal payload, reloaded.save_data.b,
      "decompressed bytes must equal original input"
  end

  test "save_data is stored compressed on disk (smaller than raw input)" do
    # Use a highly compressible payload that mimics SRAM: ~512KB of mostly
    # zero bytes. gzip should pull this down by 95%+.
    payload = ("\x00".b * 500_000) + SecureRandom.random_bytes(12_000)
    session = create(:soul_link_emulator_session, soul_link_run: @run, save_data: payload)

    raw_on_disk = session.attributes_before_type_cast["save_data"]
    raw_bytes = raw_on_disk.is_a?(String) ? raw_on_disk : raw_on_disk.to_s
    assert raw_bytes.bytesize < payload.bytesize,
      "expected gzipped on-disk bytes (#{raw_bytes.bytesize}) to be smaller than raw input (#{payload.bytesize})"
    # Ratio sanity check: highly compressible padding should compress by at
    # least 50%. Real Platinum saves do far better — ~85-95% — but we keep
    # the threshold conservative for cross-platform zlib variance.
    assert raw_bytes.bytesize < (payload.bytesize / 2),
      "expected at least 50% compression on highly-redundant SRAM-like payload " \
      "(raw=#{payload.bytesize}, compressed=#{raw_bytes.bytesize})"
    # On-disk bytes start with the gzip magic header.
    assert raw_bytes.b.start_with?("\x1f\x8b".b),
      "on-disk bytes should start with gzip magic header"
  end

  test "save_data nil round-trips as nil" do
    session = create(:soul_link_emulator_session, soul_link_run: @run, save_data: nil)
    reloaded = SoulLinkEmulatorSession.find(session.id)
    assert_nil reloaded.save_data
  end

  test "save_data empty string round-trips as empty (no gzip overhead written)" do
    session = create(:soul_link_emulator_session, soul_link_run: @run, save_data: "")
    reloaded = SoulLinkEmulatorSession.find(session.id)
    # Coder returns empty bytes for empty input — preserves the legacy
    # contract that GET save_data returns 204 when blank.
    assert_equal "", reloaded.save_data.to_s
    raw = reloaded.attributes_before_type_cast["save_data"]
    raw_bytes = raw.is_a?(String) ? raw : raw.to_s
    assert raw_bytes.bytesize == 0 || !raw_bytes.b.start_with?("\x1f\x8b".b),
      "empty input should not produce a gzip header on disk"
  end

  # Defensive: if a row from before this coder shipped contains plaintext
  # bytes, the loader passes them through unchanged. Once verified that all
  # production rows are gzipped, this branch can be removed.
  test "save_data load passes through plaintext bytes lacking gzip magic" do
    plaintext = "LEGACY_PLAINTEXT_SAVE_BYTES_\x00\x01\x02".b
    # Simulate a legacy row by writing directly through update_columns,
    # which bypasses the serialization coder.
    session = create(:soul_link_emulator_session, soul_link_run: @run)
    session.update_columns(save_data: plaintext)

    reloaded = SoulLinkEmulatorSession.find(session.id)
    assert_equal plaintext, reloaded.save_data.b,
      "plaintext legacy values must pass through unchanged"
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
