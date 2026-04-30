require "test_helper"

class SaveSlotsControllerTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728
  ARATY = 600802903967531093

  setup do
    @run = soul_link_runs(:active_run)
    @sess = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: GREY)
  end

  # --- auth ---------------------------------------------------------------

  test "index requires login" do
    get emulator_save_slots_path
    assert_redirected_to login_path
  end

  test "create requires login" do
    post emulator_save_slots_path
    assert_redirected_to login_path
  end

  test "update requires login" do
    patch emulator_save_slot_path(slot_number: 1)
    assert_redirected_to login_path
  end

  test "destroy requires login" do
    delete emulator_save_slot_path(slot_number: 1)
    assert_redirected_to login_path
  end

  test "restore requires login" do
    post restore_emulator_save_slot_path(slot_number: 1)
    assert_redirected_to login_path
  end

  test "download requires login" do
    get download_emulator_save_slot_path(slot_number: 1)
    assert_redirected_to login_path
  end

  # --- index --------------------------------------------------------------

  test "index returns 404 when caller has no claimed session" do
    login_as(ARATY)
    get emulator_save_slots_path
    assert_response :not_found
  end

  test "index returns empty slots list when no slots exist yet" do
    login_as(GREY)
    get emulator_save_slots_path
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body["slots"]
    assert_nil body["active_slot"]
    assert_equal SoulLinkEmulatorSaveSlot::MAX_SLOT, body["max"]
  end

  test "index returns the player's own slots ordered by slot_number" do
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @sess, slot_number: 3)
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @sess, slot_number: 1)
    @sess.update!(active_save_slot: 1)
    login_as(GREY)

    get emulator_save_slots_path
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [ 1, 3 ], body["slots"].map { |s| s["slot_number"] }
    assert_equal 1, body["active_slot"]
  end

  test "index does NOT leak other players' slots" do
    other = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: ARATY)
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: other, slot_number: 1)
    login_as(GREY)

    get emulator_save_slots_path
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal [], body["slots"]
  end

  # --- create -------------------------------------------------------------

  test "create writes bytes to the first empty slot and sets active_save_slot" do
    payload = "BYTES_FOR_FIRST_SAVE".b
    login_as(GREY)

    post emulator_save_slots_path,
         params: payload,
         headers: {
           "Content-Type" => "application/octet-stream",
           "X-CSRF-Token" => session[:_csrf_token].to_s
         }
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal 1, body["slot_number"]

    @sess.reload
    assert_equal 1, @sess.save_slots.count
    assert_equal 1, @sess.active_save_slot
    assert_equal payload, @sess.save_slots.first.save_data.b
  end

  test "create skips occupied slots and writes to the lowest empty slot" do
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @sess, slot_number: 1)
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @sess, slot_number: 2)
    payload = "BYTES_FOR_NEXT".b
    login_as(GREY)

    post emulator_save_slots_path,
         params: payload,
         headers: {
           "Content-Type" => "application/octet-stream",
           "X-CSRF-Token" => session[:_csrf_token].to_s
         }
    assert_response :created
    body = JSON.parse(response.body)
    assert_equal 3, body["slot_number"]

    @sess.reload
    assert_equal 3, @sess.active_save_slot
    assert_equal payload, @sess.save_slots.find_by(slot_number: 3).save_data.b
  end

  test "create returns 409 with all slots when every slot is full" do
    (1..5).each do |n|
      create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @sess, slot_number: n)
    end
    @sess.update!(active_save_slot: 1)
    login_as(GREY)

    post emulator_save_slots_path,
         params: "WOULD_OVERWRITE".b,
         headers: {
           "Content-Type" => "application/octet-stream",
           "X-CSRF-Token" => session[:_csrf_token].to_s
         }
    assert_response :conflict
    body = JSON.parse(response.body)
    assert_equal "all_slots_full", body["error"]
    assert_equal 5, body["slots"].size
    assert_equal [ 1, 2, 3, 4, 5 ], body["slots"].map { |s| s["slot_number"] }
    # Active pointer must NOT have changed on a 409.
    assert_equal 1, @sess.reload.active_save_slot
  end

  test "create returns 404 when caller has no claimed session" do
    login_as(ARATY)
    post emulator_save_slots_path,
         params: "X".b,
         headers: {
           "Content-Type" => "application/octet-stream",
           "X-CSRF-Token" => session[:_csrf_token].to_s
         }
    assert_response :not_found
  end

  test "create succeeds without CSRF token (null_session bypass)" do
    payload = "BYTES_NO_CSRF".b
    login_as(GREY)

    with_forgery_protection do
      post emulator_save_slots_path,
           params: payload,
           headers: { "Content-Type" => "application/octet-stream" }
    end
    assert_response :created
  end

  test "create rejects body larger than the size cap with 413" do
    oversized = "\x00".b * (EmulatorController::MAX_SAVE_DATA_BYTES + 1)
    login_as(GREY)

    post emulator_save_slots_path,
         params: oversized,
         headers: {
           "Content-Type" => "application/octet-stream",
           "X-CSRF-Token" => session[:_csrf_token].to_s
         }
    assert_response :content_too_large
  end

  # --- update -------------------------------------------------------------

  test "update overwrites the slot's bytes and sets active_save_slot" do
    create(:soul_link_emulator_save_slot, soul_link_emulator_session: @sess, slot_number: 2,
                                          save_data: "OLD".b)
    @sess.update!(active_save_slot: 1)
    login_as(GREY)

    patch emulator_save_slot_path(slot_number: 2),
          params: "NEW_BYTES".b,
          headers: {
            "Content-Type" => "application/octet-stream",
            "X-CSRF-Token" => session[:_csrf_token].to_s
          }
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal 2, body["slot_number"]

    @sess.reload
    assert_equal 2, @sess.active_save_slot
    assert_equal "NEW_BYTES".b, @sess.save_slots.find_by(slot_number: 2).save_data.b
  end

  test "update returns 404 when slot does not exist" do
    login_as(GREY)
    patch emulator_save_slot_path(slot_number: 4),
          params: "X".b,
          headers: {
            "Content-Type" => "application/octet-stream",
            "X-CSRF-Token" => session[:_csrf_token].to_s
          }
    assert_response :not_found
  end

  test "update returns 404 when slot belongs to another player" do
    other = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: ARATY)
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: other, slot_number: 1)
    login_as(GREY)

    patch emulator_save_slot_path(slot_number: 1),
          params: "PWNED".b,
          headers: {
            "Content-Type" => "application/octet-stream",
            "X-CSRF-Token" => session[:_csrf_token].to_s
          }
    assert_response :not_found
  end

  test "update rejects body larger than the size cap with 413" do
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @sess, slot_number: 1)
    oversized = "\x00".b * (EmulatorController::MAX_SAVE_DATA_BYTES + 1)
    login_as(GREY)

    patch emulator_save_slot_path(slot_number: 1),
          params: oversized,
          headers: {
            "Content-Type" => "application/octet-stream",
            "X-CSRF-Token" => session[:_csrf_token].to_s
          }
    assert_response :content_too_large
  end

  # --- destroy ------------------------------------------------------------

  test "destroy removes the slot" do
    slot = create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @sess, slot_number: 2)
    @sess.update!(active_save_slot: 1)
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @sess, slot_number: 1)
    login_as(GREY)

    delete emulator_save_slot_path(slot_number: 2),
           headers: { "X-CSRF-Token" => session[:_csrf_token].to_s }
    assert_response :no_content
    assert_nil SoulLinkEmulatorSaveSlot.find_by(id: slot.id)
    # Active pointer is unchanged because the deleted slot wasn't active.
    assert_equal 1, @sess.reload.active_save_slot
  end

  test "destroy clears active_save_slot when the deleted slot was active" do
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @sess, slot_number: 1)
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @sess, slot_number: 3)
    @sess.update!(active_save_slot: 3)
    login_as(GREY)

    delete emulator_save_slot_path(slot_number: 3),
           headers: { "X-CSRF-Token" => session[:_csrf_token].to_s }
    assert_response :no_content
    assert_nil @sess.reload.active_save_slot
  end

  test "destroy returns 404 when slot does not exist" do
    login_as(GREY)
    delete emulator_save_slot_path(slot_number: 1),
           headers: { "X-CSRF-Token" => session[:_csrf_token].to_s }
    assert_response :not_found
  end

  test "destroy returns 404 when slot belongs to another player" do
    other = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: ARATY)
    other_slot = create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: other, slot_number: 1)
    login_as(GREY)

    delete emulator_save_slot_path(slot_number: 1),
           headers: { "X-CSRF-Token" => session[:_csrf_token].to_s }
    assert_response :not_found
    # Other player's slot untouched.
    assert_not_nil SoulLinkEmulatorSaveSlot.find_by(id: other_slot.id)
  end

  # --- restore ------------------------------------------------------------

  test "restore sets active_save_slot to the chosen slot without mutating bytes" do
    create(:soul_link_emulator_save_slot, soul_link_emulator_session: @sess, slot_number: 1, save_data: "FIRST".b)
    create(:soul_link_emulator_save_slot, soul_link_emulator_session: @sess, slot_number: 4, save_data: "FOURTH".b)
    @sess.update!(active_save_slot: 1)
    login_as(GREY)

    post restore_emulator_save_slot_path(slot_number: 4),
         headers: { "X-CSRF-Token" => session[:_csrf_token].to_s }
    assert_response :no_content

    @sess.reload
    assert_equal 4, @sess.active_save_slot
    # Bytes for both slots intact.
    assert_equal "FIRST",  @sess.save_slots.find_by(slot_number: 1).save_data.b
    assert_equal "FOURTH", @sess.save_slots.find_by(slot_number: 4).save_data.b
  end

  test "restore returns 404 when slot does not exist" do
    login_as(GREY)
    post restore_emulator_save_slot_path(slot_number: 5),
         headers: { "X-CSRF-Token" => session[:_csrf_token].to_s }
    assert_response :not_found
  end

  test "restore returns 404 when slot belongs to another player" do
    other = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: ARATY)
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: other, slot_number: 1)
    login_as(GREY)

    post restore_emulator_save_slot_path(slot_number: 1),
         headers: { "X-CSRF-Token" => session[:_csrf_token].to_s }
    assert_response :not_found
    # Caller's session pointer must NOT have changed.
    assert_nil @sess.reload.active_save_slot
  end

  # --- download -----------------------------------------------------------

  test "download serves the slot's bytes as application/octet-stream" do
    payload = "PLATINUM_SLOT_BYTES_x01".b
    create(:soul_link_emulator_save_slot, soul_link_emulator_session: @sess, slot_number: 2, save_data: payload)
    login_as(GREY)

    get download_emulator_save_slot_path(slot_number: 2)
    assert_response :success
    assert_equal "application/octet-stream", response.media_type
    assert_equal payload, response.body.b
    assert_match(/pokemon-platinum-slot2\.sav/, response.headers["Content-Disposition"].to_s)
  end

  test "download returns 204 when the slot has no bytes" do
    create(:soul_link_emulator_save_slot, soul_link_emulator_session: @sess, slot_number: 1, save_data: nil)
    login_as(GREY)

    get download_emulator_save_slot_path(slot_number: 1)
    assert_response :no_content
  end

  test "download returns 404 when slot does not exist" do
    login_as(GREY)
    get download_emulator_save_slot_path(slot_number: 1)
    assert_response :not_found
  end

  test "download returns 404 when slot belongs to another player" do
    other = create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: ARATY)
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: other, slot_number: 1)
    login_as(GREY)

    get download_emulator_save_slot_path(slot_number: 1)
    assert_response :not_found
  end

  # --- cross-player authz (defense in depth) ------------------------------
  #
  # Every action above already asserts the cross-player 404 on a per-action
  # basis. This block re-states the contract loud and clear: the controller
  # resolves @session by current_user_id, so an authenticated player simply
  # cannot reach another player's slots, regardless of the slot_number in
  # the URL or any body content.

  test "cross-player attempt: ARATY cannot read GREY's slots via index" do
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @sess, slot_number: 1)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: ARATY)
    login_as(ARATY)

    get emulator_save_slots_path
    assert_response :success
    body = JSON.parse(response.body)
    # ARATY sees their own (empty) list, NOT GREY's slot 1.
    assert_equal [], body["slots"]
  end

  test "cross-player attempt: PATCH to GREY's slot fails for ARATY" do
    create(:soul_link_emulator_save_slot, :filled, soul_link_emulator_session: @sess, slot_number: 1)
    create(:soul_link_emulator_session, :ready, soul_link_run: @run, discord_user_id: ARATY)
    login_as(ARATY)

    patch emulator_save_slot_path(slot_number: 1),
          params: "ATTACK".b,
          headers: {
            "Content-Type" => "application/octet-stream",
            "X-CSRF-Token" => session[:_csrf_token].to_s
          }
    assert_response :not_found
    # GREY's slot bytes unchanged.
    assert_equal "PLATINUM_SRAM_BYTES_\x00\x01\x02".b,
                 @sess.save_slots.find_by(slot_number: 1).save_data.b
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
