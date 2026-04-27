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

  private

  def with_forgery_protection
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = original
  end
end
