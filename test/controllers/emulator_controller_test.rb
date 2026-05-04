require "test_helper"

class EmulatorControllerTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728
  ARATY = 600802903967531093
  SCYTHE = 189518174125817856

  setup do
    @run = create(:soul_link_run)
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

  test "save_data DELETE requires login" do
    delete save_data_emulator_path
    assert_redirected_to login_path
  end

  test "firmware requires login" do
    get firmware_emulator_path
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
    assert_match(/data-emulator-save-slots-url-value=/, response.body)
    assert_match(/data-emulator-core-value="melonds"/, response.body)
    assert_match(/data-emulator-pathtodata-value="\/emulatorjs\/data\/"/, response.body)
    assert_match(/data-emulator-cheats-value=/, response.body)
  end

  test "show renders save slots sidebar when session is ready" do
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    login_as(GREY)
    get emulator_path
    assert_response :success
    assert_match(/SAVE SLOTS/, response.body)
    assert_match(/data-controller="save-slots"/, response.body)
    # 5 slot cards rendered, all empty.
    (1..5).each do |n|
      assert_match Regexp.new(Regexp.escape("SLOT #{n}")), response.body
    end
  end

  test "show renders ACTIVE badge on the slot matching active_save_slot" do
    sess = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: sess, slot_number: 2)
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: sess, slot_number: 3)
    sess.update!(active_save_slot: 2)

    login_as(GREY)
    get emulator_path
    assert_response :success
    # Step 21 R3 — every slot has a state pill. The active slot pill is
    # ACTIVE; other filled slots are SAVED; unfilled slots are EMPTY.
    assert_match(/>ACTIVE</, response.body)
    assert_match(/>SAVED</, response.body)
    assert_match(/>EMPTY</, response.body)
  end

  # --- show: Step 21 R3 save-slot redesign assertions --------------------

  test "show renders the empty-slot CTA copy on unfilled slots" do
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    login_as(GREY)
    get emulator_path
    assert_response :success
    # Em-dash CTA copy on every empty slot — verbatim from the mockup.
    assert_match(/drop a save here from the emulator/, response.body)
  end

  test "show renders inline DELETE confirm markup hidden per filled slot" do
    sess = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: sess, slot_number: 1)

    login_as(GREY)
    get emulator_path
    assert_response :success
    # The DELETE trigger fires save-slots#confirmDelete (NOT confirm-modal#open).
    # Hand-written ERB attribute values aren't auto-escaped, so the literal
    # `>` survives. (Tag-helper-rendered modals like Step 20's escape it.)
    assert_match(/data-action="click->save-slots#confirmDelete"/, response.body)
    # The confirm-inline block exists in the response body, rendered hidden.
    assert_match(/class="confirm-inline" hidden/, response.body)
    # And carries the DELETE FOREVER label.
    assert_match(/DELETE FOREVER/, response.body)
  end

  test "show renders inline CLEAR ALL SLOTS confirm markup hidden in the footer" do
    sess = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: sess, slot_number: 1)

    login_as(GREY)
    get emulator_path
    assert_response :success
    # Trigger fires save-slots#confirmClearAll (NOT confirm-modal#open).
    assert_match(/data-action="click->save-slots#confirmClearAll"/, response.body)
    # And the inline confirm block is rendered with the clearAllConfirm target.
    assert_match(/data-save-slots-target="clearAllConfirm"/, response.body)
  end

  test "show does NOT render the Step-20 confirm-modal partial for any save-slot DELETE or CLEAR ALL SLOTS" do
    sess = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: sess, slot_number: 1)
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: sess, slot_number: 2)

    login_as(GREY)
    get emulator_path
    assert_response :success
    # Step 21 R3 — the per-slot DELETE modal ids (1..5) and the
    # CLEAR ALL SLOTS modal id should NOT appear; the inline-confirm
    # pattern replaced them.
    (1..5).each do |n|
      assert_no_match(/id="delete-slot-#{n}-confirm"/, response.body)
    end
    assert_no_match(/id="clear-all-slots-confirm"/, response.body)
  end

  test "show body never contains the peso glyph (Step 21 R3 dropped the money symbol)" do
    sess = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    create(:soul_link_emulator_save_slot,
           soul_link_emulator_session: sess,
           slot_number: 1,
           save_data: "EXISTING".b,
           parsed_trainer_name: "Lyra",
           parsed_money: 12_345,
           parsed_at: Time.current)
    sess.update!(active_save_slot: 1)

    login_as(GREY)
    get emulator_path
    assert_response :success
    # Mockup explicitly drops the Pokédollar glyph on both surfaces.
    assert_no_match(/&#8369;/, response.body)
    assert_no_match(/₱/, response.body)
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

    [ s1, s2, s3, s4 ].each do |s|
      assert_match Regexp.new(Regexp.escape(s.seed)), response.body,
        "expected seed #{s.seed} in roster body"
    end

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
    assert_no_match(/>YOU</, response.body)
  end

  test "show roster renders player names and Unclaimed entries" do
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: ARATY)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run) # unclaimed
    create(:soul_link_emulator_session, :ready, soul_link_run: @run) # unclaimed

    login_as(GREY)
    get emulator_path
    assert_response :success

    assert_match(/RUN ROSTER/, response.body)
    assert_match(/Grey/, response.body)
    assert_match(/Unclaimed/, response.body)
    # YOU badge + 4px-border were removed in Step 9 because preserving
    # them across Turbo Stream broadcasts would require passing
    # current_user_id into a model callback (a layer violation). The
    # player_label still disambiguates which card is theirs. Tracked as
    # a Known Gap in BUILD-LOG.
  end

  # --- show: parsed save fields in roster cards (other players) ----------
  #
  # Phase 1 SRAM parser populates parsed_* columns asynchronously on the
  # active save slot; the run-roster sidebar renders OTHER players' parsed
  # info (your own parsed info shows in the slot column on the left
  # instead).

  test "show roster renders parsed_trainer_name, money, play time, and badges for OTHER players" do
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    other = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: ARATY)
    create(:soul_link_emulator_save_slot,
           soul_link_emulator_session: other,
           slot_number: 1,
           save_data: "EXISTING".b,
           parsed_trainer_name: "Lyra",
           parsed_money: 12_345,
           parsed_play_seconds: 5 * 3600 + 30 * 60,
           parsed_badges: 4,
           parsed_at: Time.current)
    other.update!(active_save_slot: 1)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run)

    login_as(GREY)
    get emulator_path
    assert_response :success

    assert_match(/Lyra/, response.body)
    assert_match(/12,345/, response.body)
    assert_match(/5h 30m/, response.body)
    # Step 21 R3 — badges live in a stat tile, no "/ 8" suffix.
    assert_match(%r{<div class="lbl">BADGES</div>\s*<div class="val">4</div>}, response.body)
  end

  test "show roster omits parsed_* lines when no slot has parsed data" do
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run)

    login_as(GREY)
    get emulator_path
    assert_response :success

    assert_match(/RUN ROSTER/, response.body)
    # Step 21 R3 — Trainer / Map / Money rows live inside <details>STATS
    # and only render when the parsed_* field is present. With no parsed
    # data, the inner rows collapse — assert their LABELS don't appear.
    assert_no_match(/<span class="lbl">TRAINER<\/span>/, response.body)
    assert_no_match(/<span class="lbl">MAP<\/span>/, response.body)
    assert_no_match(/<span class="lbl">MONEY<\/span>/, response.body)
  end

  test "show roster shows '0 / 8' badges for a parsed other-player session with zero badges" do
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    other = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: ARATY)
    create(:soul_link_emulator_save_slot,
           soul_link_emulator_session: other,
           slot_number: 1,
           save_data: "EXISTING".b,
           parsed_trainer_name: "Bob",
           parsed_money: 0,
           parsed_play_seconds: 0,
           parsed_badges: 0,
           parsed_at: Time.current)
    other.update!(active_save_slot: 1)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run)

    login_as(GREY)
    get emulator_path
    assert_response :success

    assert_match(/Bob/, response.body)
    assert_match(/0h 0m/, response.body)
    # Step 21 R3 — badges live in a stat tile, no "/ 8" suffix.
    assert_match(%r{<div class="lbl">BADGES</div>\s*<div class="val">0</div>}, response.body)
  end

  # --- show: cheats payload ----------------------------------------------

  test "show renders empty cheats data attribute when no cheats configured" do
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
    SoulLink::GameState.stub(:cheats, {}) do
      login_as(GREY)
      get emulator_path
    end
    assert_response :success
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

    claimed_count = @run.soul_link_emulator_sessions.where(discord_user_id: GREY).count
    assert_equal 1, claimed_count
    assert_equal 2, call_count, "expected exactly two claim! attempts (one losing, one winning retry)"
    # Sanity: both `losing` and `winning` exist; one of them got claimed.
    assert [ losing.reload.discord_user_id, winning.reload.discord_user_id ].include?(GREY)
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

  # --- save_data GET (sources from active save slot) ---------------------

  test "save_data GET returns 204 when session has no active slot" do
    create(:soul_link_emulator_session,
           :ready,
           soul_link_run: @run,
           discord_user_id: GREY)
    login_as(GREY)
    get save_data_emulator_path
    assert_response :no_content
  end

  test "save_data GET returns 204 when active slot has nil bytes" do
    sess = create(:soul_link_emulator_session,
                  :ready,
                  soul_link_run: @run,
                  discord_user_id: GREY)
    create(:soul_link_emulator_save_slot, soul_link_emulator_session: sess, slot_number: 1, save_data: nil)
    sess.update!(active_save_slot: 1)
    login_as(GREY)
    get save_data_emulator_path
    assert_response :no_content
  end

  test "save_data GET returns 204 when active slot has empty bytes" do
    sess = create(:soul_link_emulator_session,
                  :ready,
                  soul_link_run: @run,
                  discord_user_id: GREY)
    create(:soul_link_emulator_save_slot, soul_link_emulator_session: sess, slot_number: 1, save_data: "")
    sess.update!(active_save_slot: 1)
    login_as(GREY)
    get save_data_emulator_path
    assert_response :no_content
  end

  test "save_data GET sends the active slot's bytes when present" do
    payload = "PLATINUM_SRAM_DUMP_BYTES_x01x02x03".b
    sess = create(:soul_link_emulator_session,
                  :ready,
                  soul_link_run: @run,
                  discord_user_id: GREY)
    create(:soul_link_emulator_save_slot, soul_link_emulator_session: sess, slot_number: 1, save_data: "OTHER".b)
    create(:soul_link_emulator_save_slot, soul_link_emulator_session: sess, slot_number: 2, save_data: payload)
    sess.update!(active_save_slot: 2)
    login_as(GREY)
    get save_data_emulator_path
    assert_response :success
    assert_equal "application/octet-stream", response.media_type
    assert_equal payload, response.body.b
  end

  # --- save_data DELETE (wipes ALL slots + clears active pointer) -------

  test "save_data DELETE wipes all slots and clears active_save_slot" do
    sess = create(:soul_link_emulator_session,
                  :ready,
                  soul_link_run: @run,
                  discord_user_id: GREY)
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: sess, slot_number: 1)
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: sess, slot_number: 3)
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: sess, slot_number: 5)
    sess.update!(active_save_slot: 3)
    login_as(GREY)

    delete save_data_emulator_path,
           headers: { "X-CSRF-Token" => session[:_csrf_token].to_s }
    assert_response :no_content

    sess.reload
    assert_equal 0, sess.save_slots.count
    assert_nil sess.active_save_slot
  end

  test "save_data DELETE returns 404 when caller has no claimed session" do
    login_as(ARATY)
    delete save_data_emulator_path,
           headers: { "X-CSRF-Token" => session[:_csrf_token].to_s }
    assert_response :not_found
  end

  test "save_data DELETE only wipes the caller's own slots, not other players'" do
    mine = create(:soul_link_emulator_session,
                  :ready,
                  soul_link_run: @run,
                  discord_user_id: GREY)
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: mine, slot_number: 1)
    other = create(:soul_link_emulator_session,
                   :ready,
                   soul_link_run: @run,
                   discord_user_id: ARATY)
    other_slot = create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: other, slot_number: 1)
    login_as(GREY)

    delete save_data_emulator_path,
           headers: { "X-CSRF-Token" => session[:_csrf_token].to_s }
    assert_response :no_content

    assert_equal 0, mine.reload.save_slots.count
    # Other player's slot untouched.
    assert_not_nil SoulLinkEmulatorSaveSlot.find_by(id: other_slot.id)
  end

  # --- firmware -----------------------------------------------------------

  test "firmware serves the configured ZIP when present" do
    Tempfile.create([ "firmware", ".zip" ]) do |f|
      f.write("FAKE_FIRMWARE_ZIP_CONTENT".b)
      f.flush

      with_firmware_path(f.path) do
        login_as(GREY)
        get firmware_emulator_path
        assert_response :success
        assert_equal "application/zip", response.media_type
        assert_equal "FAKE_FIRMWARE_ZIP_CONTENT".b, response.body.b
      end
    end
  end

  test "firmware returns 404 when configured ZIP is missing" do
    with_firmware_path("/nonexistent/path/firmware.zip") do
      login_as(GREY)
      get firmware_emulator_path
      assert_response :not_found
    end
  end

  test "firmware sets a Cache-Control header so the browser skips re-download on each page load" do
    Tempfile.create([ "firmware", ".zip" ]) do |f|
      f.write("X".b)
      f.flush

      with_firmware_path(f.path) do
        login_as(GREY)
        get firmware_emulator_path
        assert_response :success
        # expires_in 1.day, public: false → "max-age=86400, private"
        assert_match(/max-age=\d+/, response.headers["Cache-Control"].to_s)
        assert_match(/private/,     response.headers["Cache-Control"].to_s)
      end
    end
  end

  private

  def with_firmware_path(path)
    original = ENV["SOUL_LINK_FIRMWARE_PATH"]
    ENV["SOUL_LINK_FIRMWARE_PATH"] = path
    yield
  ensure
    ENV["SOUL_LINK_FIRMWARE_PATH"] = original
  end
end
