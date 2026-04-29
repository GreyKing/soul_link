require "test_helper"

class EmulatorControllerTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728
  ARATY = 600802903967531093
  SCYTHE = 189518174125817856

  setup do
    @run = soul_link_runs(:active_run)
  end

  # --- auth ---------------------------------------------------------------

  test "show requires login" do
    get emulator_path
    assert_redirected_to login_path
  end

  test "rom requires login" do
    get rom_emulator_path
    assert_redirected_to login_path
  end

  test "save_data GET requires login" do
    get save_data_emulator_path
    assert_redirected_to login_path
  end

  test "save_data PATCH requires login" do
    patch save_data_emulator_path
    assert_redirected_to login_path
  end

  # --- show: no active run ------------------------------------------------

  test "show renders 'no active run' when guild has no active run" do
    @run.update!(active: false)
    login_as(GREY)
    get emulator_path
    assert_response :success
    assert_match(/NO ACTIVE RUN/, response.body)
  end

  # --- show: emulator_status :none ----------------------------------------

  test "show renders 'roms not generated yet' when no sessions exist" do
    login_as(GREY)
    assert_equal :none, @run.emulator_status
    get emulator_path
    assert_response :success
    assert_match(/ROMS NOT GENERATED YET/, response.body)
  end

  # --- show: all claimed --------------------------------------------------

  test "show renders 'no rom available' when all sessions are claimed by others" do
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: ARATY)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: SCYTHE)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: 111)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: 222)

    login_as(GREY)
    get emulator_path
    assert_response :success
    assert_match(/NO ROM AVAILABLE/, response.body)
  end

  # --- show: auto-claim happy path ----------------------------------------

  test "show auto-claims first unclaimed ready session for the player" do
    s1 = create(:soul_link_emulator_session, :ready, soul_link_run: @run)
    s2 = create(:soul_link_emulator_session, :ready, soul_link_run: @run)
    s3 = create(:soul_link_emulator_session, :ready, soul_link_run: @run)
    s4 = create(:soul_link_emulator_session, :ready, soul_link_run: @run)

    login_as(GREY)
    assert_no_difference "SoulLinkEmulatorSession.count" do
      get emulator_path
    end
    assert_response :success

    claimed = @run.soul_link_emulator_sessions.where(discord_user_id: GREY)
    assert_equal 1, claimed.count, "exactly one session should be claimed by the player"
    # Sanity: one of the four originals got the claim, none were destroyed.
    assert_equal 4, @run.soul_link_emulator_sessions.count
    assert [ s1, s2, s3, s4 ].any? { |s| s.reload.discord_user_id == GREY }
  end

  test "show does not re-claim when player already has a session" do
    mine = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    other = create(:soul_link_emulator_session, :ready, soul_link_run: @run)

    login_as(GREY)
    get emulator_path
    assert_response :success

    assert_equal GREY, mine.reload.discord_user_id
    assert_nil other.reload.discord_user_id
  end

  # --- show: claimed-but-not-ready ---------------------------------------

  test "show renders 'rom generating' when session is pending" do
    create(:soul_link_emulator_session, soul_link_run: @run, discord_user_id: GREY, status: "pending")
    login_as(GREY)
    get emulator_path
    assert_response :success
    assert_match(/ROM GENERATING/, response.body)
  end

  test "show renders 'rom generating' when session is generating" do
    create(:soul_link_emulator_session, soul_link_run: @run, discord_user_id: GREY, status: "generating")
    login_as(GREY)
    get emulator_path
    assert_response :success
    assert_match(/ROM GENERATING/, response.body)
  end

  test "show renders 'rom generation failed' with error_message when session failed" do
    create(:soul_link_emulator_session,
           soul_link_run: @run,
           discord_user_id: GREY,
           status: "failed",
           error_message: "randomizer crashed: bad seed")
    login_as(GREY)
    get emulator_path
    assert_response :success
    assert_match(/ROM GENERATION FAILED/, response.body)
    assert_match(/randomizer crashed: bad seed/, response.body)
  end

  # --- show: ready --------------------------------------------------------

  test "show renders emulator stage when session is ready and claimed" do
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    login_as(GREY)
    get emulator_path
    assert_response :success
    assert_match(/data-controller="emulator"/, response.body)
    assert_match(/data-emulator-rom-url-value=/, response.body)
    assert_match(/data-emulator-save-data-url-value=/, response.body)
    assert_match(/data-emulator-core-value="melonds"/, response.body)
    assert_match(/data-emulator-pathtodata-value="\/emulatorjs\/data\/"/, response.body)
    assert_match(/data-emulator-cheats-value=/, response.body)
  end

  # --- show: run roster sidebar ------------------------------------------

  test "show renders run roster with all 4 sessions in id order on ready state" do
    s1 = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY,    seed: "seed-roster-1")
    s2 = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: ARATY,   seed: "seed-roster-2")
    s3 = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: SCYTHE,  seed: "seed-roster-3")
    s4 = create(:soul_link_emulator_session, :ready, soul_link_run: @run,                            seed: "seed-roster-4")

    login_as(GREY)
    get emulator_path
    assert_response :success

    # All four sessions appear (verified via their unique seeds).
    [ s1, s2, s3, s4 ].each do |s|
      assert_match Regexp.new(Regexp.escape(s.seed)), response.body,
        "expected seed #{s.seed} in roster body"
    end

    # Cards must render in id order — assert seeds appear in ascending-id order
    # in the response body. Sort by id (creation order), then check positions.
    ordered = [ s1, s2, s3, s4 ].sort_by(&:id)
    positions = ordered.map { |s| response.body.index(s.seed) }
    assert positions.all?, "all seeds must be present in the body"
    assert_equal positions, positions.sort,
      "roster cards must render in id-ascending order"
  end

  test "show roster does NOT render when there is no active run" do
    @run.update!(active: false)
    login_as(GREY)
    get emulator_path
    assert_response :success
    assert_no_match(/RUN ROSTER/, response.body)
  end

  test "show roster does NOT render when session is generating" do
    create(:soul_link_emulator_session, soul_link_run: @run, discord_user_id: GREY, status: "generating")
    login_as(GREY)
    get emulator_path
    assert_response :success
    assert_no_match(/RUN ROSTER/, response.body)
  end

  test "show roster does NOT render when session has failed" do
    create(:soul_link_emulator_session,
           soul_link_run: @run,
           discord_user_id: GREY,
           status: "failed",
           error_message: "boom")
    login_as(GREY)
    get emulator_path
    assert_response :success
    assert_no_match(/RUN ROSTER/, response.body)
    # Defensive: the YOU badge should not leak into non-ready states.
    assert_no_match(/>YOU</, response.body)
  end

  test "show roster renders player names, YOU badge, and Unclaimed entries" do
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: ARATY)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run) # unclaimed
    create(:soul_link_emulator_session, :ready, soul_link_run: @run) # unclaimed

    login_as(GREY)
    get emulator_path
    assert_response :success

    # Section header.
    assert_match(/RUN ROSTER/, response.body)
    # Current player's display name (from settings.yml: GREY → "Grey").
    assert_match(/Grey/, response.body)
    # YOU badge for the current player's card.
    assert_match(/>YOU</, response.body)
    # At least one Unclaimed entry (we created two unclaimed sessions).
    assert_match(/Unclaimed/, response.body)
  end

  # --- show: cheats payload ----------------------------------------------

  test "show renders empty cheats data attribute when no cheats configured" do
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    SoulLink::GameState.stub(:cheats, {}) do
      login_as(GREY)
      get emulator_path
    end
    assert_response :success
    # `[].to_json` HTML-escapes to `[]` inside the attribute.
    assert_match(/data-emulator-cheats-value="\[\]"/, response.body)
  end

  test "show renders populated cheats data attribute when cheats are configured" do
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    payload = [
      { "name" => "Walk Through Walls", "enabled" => true, "code" => "02000000 12345678" }
    ]
    SoulLink::GameState.stub(:cheats, { "action_replay" => payload }) do
      login_as(GREY)
      get emulator_path
    end
    assert_response :success
    assert_match(/data-emulator-cheats-value=/, response.body)
    assert_match(/Walk Through Walls/, response.body)
    # AR codes contain spaces; ERB JSON escaping leaves them as-is. Probe the
    # opcode prefix so we know the code body landed in the attribute.
    assert_match(/02000000/, response.body)
  end

  test "show does NOT render cheats data attribute when state is not ready (no active run)" do
    @run.update!(active: false)
    login_as(GREY)
    get emulator_path
    assert_response :success
    assert_no_match(/data-emulator-cheats-value=/, response.body)
  end

  test "show does NOT render cheats data attribute when session is generating" do
    create(:soul_link_emulator_session, soul_link_run: @run, discord_user_id: GREY, status: "generating")
    login_as(GREY)
    get emulator_path
    assert_response :success
    assert_no_match(/data-emulator-cheats-value=/, response.body)
  end

  test "show does NOT render cheats data attribute when session has failed" do
    create(:soul_link_emulator_session,
           soul_link_run: @run,
           discord_user_id: GREY,
           status: "failed",
           error_message: "boom")
    login_as(GREY)
    get emulator_path
    assert_response :success
    assert_no_match(/data-emulator-cheats-value=/, response.body)
  end

  # --- show: claim race ---------------------------------------------------

  # Simulates the case where two requests for the same player race past
  # the SELECT-unclaimed step; the first wins, the second's claim! raises
  # AlreadyClaimedError and we retry against a different unclaimed row.
  test "show retries on AlreadyClaimedError and claims a different unclaimed session" do
    losing = create(:soul_link_emulator_session, :ready, soul_link_run: @run)
    winning = create(:soul_link_emulator_session, :ready, soul_link_run: @run)

    # Stub `claim!` so the first call (against `losing`) raises and the
    # second call (against `winning`) succeeds. Use a counter so we don't
    # depend on object identity (set_session re-queries between attempts).
    call_count = 0
    SoulLinkEmulatorSession.class_eval do
      alias_method :__orig_claim!, :claim!
      define_method(:claim!) do |uid|
        call_count += 1
        if call_count == 1
          raise SoulLinkEmulatorSession::AlreadyClaimedError, "race"
        else
          __orig_claim!(uid)
        end
      end
    end

    begin
      login_as(GREY)
      get emulator_path
      assert_response :success
    ensure
      SoulLinkEmulatorSession.class_eval do
        alias_method :claim!, :__orig_claim!
        remove_method :__orig_claim!
      end
    end

    # Exactly one session should now be claimed by the player.
    claimed_count = @run.soul_link_emulator_sessions.where(discord_user_id: GREY).count
    assert_equal 1, claimed_count
    assert_equal 2, call_count, "expected exactly two claim! attempts (one losing, one winning retry)"
  end

  # --- rom ----------------------------------------------------------------

  test "rom returns 404 when session is not ready" do
    create(:soul_link_emulator_session,
           soul_link_run: @run,
           discord_user_id: GREY,
           status: "generating")
    login_as(GREY)
    get rom_emulator_path
    assert_response :not_found
  end

  test "rom returns 404 when no session for player" do
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: ARATY)
    login_as(GREY)
    get rom_emulator_path
    # set_session won't auto-claim on rom action? Actually it will — same
    # before_action. The player gets ARATY's row claimed first, then we
    # check: ARATY's already claimed, so unclaimed.first is nil, @session
    # is nil, head :not_found.
    assert_response :not_found
  end

  test "rom returns 404 when rom_full_path does not exist on disk" do
    create(:soul_link_emulator_session,
           :ready,
           soul_link_run: @run,
           discord_user_id: GREY,
           rom_path: "storage/roms/randomized/test/does_not_exist.nds")
    login_as(GREY)
    get rom_emulator_path
    assert_response :not_found
  end

  test "rom sends the file when ready and present on disk" do
    rom_bytes = "FAKE_NDS_BYTES_FOR_TEST".b
    Tempfile.open([ "test_rom", ".nds" ]) do |f|
      f.binmode
      f.write(rom_bytes)
      f.flush

      relative = Pathname.new(f.path).relative_path_from(Rails.root).to_s
      create(:soul_link_emulator_session,
             :ready,
             soul_link_run: @run,
             discord_user_id: GREY,
             rom_path: relative)

      login_as(GREY)
      get rom_emulator_path
      assert_response :success
      assert_equal "application/octet-stream", response.media_type
      assert_equal rom_bytes, response.body.b
    end
  end

  # --- save_data GET ------------------------------------------------------

  test "save_data GET returns 204 when save_data is nil" do
    create(:soul_link_emulator_session,
           :ready,
           soul_link_run: @run,
           discord_user_id: GREY,
           save_data: nil)
    login_as(GREY)
    get save_data_emulator_path
    assert_response :no_content
  end

  test "save_data GET returns 204 when save_data is empty bytes" do
    create(:soul_link_emulator_session,
           :ready,
           soul_link_run: @run,
           discord_user_id: GREY,
           save_data: "")
    login_as(GREY)
    get save_data_emulator_path
    assert_response :no_content
  end

  test "save_data GET sends the bytes when present" do
    payload = "PLATINUM_SRAM_DUMP_BYTES_x01x02x03".b
    create(:soul_link_emulator_session,
           :ready,
           soul_link_run: @run,
           discord_user_id: GREY,
           save_data: payload)
    login_as(GREY)
    get save_data_emulator_path
    assert_response :success
    assert_equal "application/octet-stream", response.media_type
    assert_equal payload, response.body.b
  end

  # --- save_data PATCH ----------------------------------------------------

  test "save_data PATCH writes the request body to the session" do
    sess = create(:soul_link_emulator_session,
                  :ready,
                  soul_link_run: @run,
                  discord_user_id: GREY)
    login_as(GREY)

    payload = "NEW_SAVE_BYTES_\x00\x01\x02".b
    patch save_data_emulator_path,
          params: payload,
          headers: {
            "Content-Type" => "application/octet-stream",
            "X-CSRF-Token" => session[:_csrf_token].to_s
          }
    assert_response :no_content
    assert_equal payload, sess.reload.save_data.to_s.b
  end

  test "save_data PATCH succeeds without a CSRF token (null_session bypass)" do
    sess = create(:soul_link_emulator_session,
                  :ready,
                  soul_link_run: @run,
                  discord_user_id: GREY)
    login_as(GREY)

    payload = "BYTES_WITHOUT_CSRF".b
    # Force forgery protection on for this test — controllers default to
    # off in test env, which would make the bypass test trivially pass.
    with_forgery_protection do
      patch save_data_emulator_path,
            params: payload,
            headers: { "Content-Type" => "application/octet-stream" }
    end

    assert_response :no_content
    assert_equal payload, sess.reload.save_data.to_s.b
  end

  # --- save_data PATCH size cap -------------------------------------------
  #
  # The MAX_SAVE_DATA_BYTES guard rejects any inbound body larger than the
  # cap with 413 (Payload Too Large) — ideally before reading the body, but
  # the post-read check is the safety net for clients that lie about
  # Content-Length or use chunked encoding without one.

  test "save_data PATCH rejects body larger than the size cap with 413" do
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    login_as(GREY)

    # Just over the cap. We send 2MB + 1 byte. Use a payload that's mostly
    # zeros so we don't blow up the test runner's memory.
    oversized = "\x00".b * (EmulatorController::MAX_SAVE_DATA_BYTES + 1)
    patch save_data_emulator_path,
          params: oversized,
          headers: {
            "Content-Type" => "application/octet-stream",
            "X-CSRF-Token" => session[:_csrf_token].to_s
          }
    assert_response :content_too_large
  end

  test "save_data PATCH accepts a body at exactly the size cap" do
    sess = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    login_as(GREY)

    at_cap = "\x00".b * EmulatorController::MAX_SAVE_DATA_BYTES
    patch save_data_emulator_path,
          params: at_cap,
          headers: {
            "Content-Type" => "application/octet-stream",
            "X-CSRF-Token" => session[:_csrf_token].to_s
          }
    assert_response :no_content
    # Round-trip the bytes through gzip serialization.
    assert_equal at_cap.bytesize, sess.reload.save_data.bytesize
  end

  test "save_data PATCH round-trips through gzip compression" do
    sess = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    login_as(GREY)

    # Mostly-zero payload (~256KB) — exercises the compression path with a
    # realistic SRAM-shape input. Random bytes prevent zlib from going crazy.
    payload = ("\x00".b * 250_000) + SecureRandom.random_bytes(6_000)
    patch save_data_emulator_path,
          params: payload,
          headers: {
            "Content-Type" => "application/octet-stream",
            "X-CSRF-Token" => session[:_csrf_token].to_s
          }
    assert_response :no_content

    sess.reload
    assert_equal payload.bytesize, sess.save_data.bytesize
    assert_equal payload, sess.save_data.b

    # On-disk size should be much smaller than what the client sent.
    raw = sess.attributes_before_type_cast["save_data"]
    raw_bytes = raw.is_a?(String) ? raw : raw.to_s
    assert raw_bytes.bytesize < payload.bytesize,
      "expected on-disk bytes (#{raw_bytes.bytesize}) to be smaller than raw input (#{payload.bytesize})"
  end

  private

  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
