# RESTful slot management for the player's own emulator session. Each
# session has up to 5 numbered slots (1..5) holding gzipped SRAM bytes. The
# frontend treats the slot column as a modal-less picker: empty slots are
# auto-targets for new saves, full slots become click-to-overwrite targets
# when the session is full.
#
# Authorization model: own-only. `set_session` resolves the player's own
# session via `current_user_id`; cross-player access is impossible — any
# attempt to touch another player's slot returns 404 because the session
# doesn't resolve.
class SaveSlotsController < ApplicationController
  include DiscordAuthentication

  MAX_SAVE_DATA_BYTES = EmulatorController::MAX_SAVE_DATA_BYTES

  before_action :require_login
  before_action :set_session
  before_action :set_slot, only: [ :update, :destroy, :restore, :download ]

  # The binary upload endpoints (POST create, PATCH update) carry an
  # octet-stream body that can't ride the standard form-CSRF token. The
  # Stimulus controllers send `X-CSRF-Token` for belt-and-suspenders, but we
  # accept the request even without one. DELETE / restore go through the
  # standard CSRF path.
  protect_from_forgery with: :null_session,
                       only: [ :create, :update ],
                       if: -> { request.post? || request.patch? }

  # GET /emulator/save_slots — JSON list of all slots for the current
  # player's session. Used by the slot column on connect and after any
  # mutation to refresh card state.
  def index
    return head :not_found if @session.nil?
    slots = @session.save_slots.order(:slot_number).map { |s| slot_payload(s) }
    render json: {
      slots: slots,
      active_slot: @session.active_save_slot,
      max: SoulLinkEmulatorSaveSlot::MAX_SLOT
    }
  end

  # POST /emulator/save_slots — write SRAM bytes to first empty slot.
  # 201 on success with slot info; 409 with current slots if all 5 are full
  # (the client then prompts overwrite via the slot column).
  #
  # The pick-empty-slot + insert pair is NOT atomic. If two concurrent POSTs
  # race past the same `pluck`, both target the same `slot_number` and the
  # DB unique index on (session_id, slot_number) rejects the second insert
  # with `RecordNotUnique`. We retry up to MAX_SLOT times — each iteration
  # re-plucks the freshly-committed used set, so a successful peer write
  # shifts us to the next empty slot. The cap is the slot range itself: if
  # MAX_SLOT concurrent inserts all win their first attempt, the table is
  # genuinely full and the next iteration's `empty.nil?` check returns 409.
  def create
    return head :not_found if @session.nil?
    return head :content_too_large if oversized?
    bytes = read_body
    return head :content_too_large if bytes.bytesize > MAX_SAVE_DATA_BYTES
    return invalid_save_response unless valid_sram?(bytes)

    slot = nil
    SoulLinkEmulatorSaveSlot::MAX_SLOT.times do
      used = @session.save_slots.pluck(:slot_number).to_set
      empty = (SoulLinkEmulatorSaveSlot::MIN_SLOT..SoulLinkEmulatorSaveSlot::MAX_SLOT).find { |n| !used.include?(n) }

      if empty.nil?
        slots = @session.save_slots.order(:slot_number).map { |s| slot_payload(s) }
        return render json: { error: "all_slots_full", slots: slots }, status: :conflict
      end

      begin
        slot = @session.save_slots.create!(slot_number: empty, save_data: bytes)
        break
      rescue ActiveRecord::RecordNotUnique
        # DB unique-index rejected our insert: another POST committed the
        # same slot_number between our pluck and our insert. Retry.
        next
      rescue ActiveRecord::RecordInvalid => e
        # Rails' model-level uniqueness validation runs a SELECT EXISTS
        # pre-check; if a peer committed our chosen slot_number between our
        # pluck and that pre-check, this raises with "Slot number has
        # already been taken". Treat the same as RecordNotUnique. Any
        # non-uniqueness validation failure is a real bug — re-raise.
        raise unless e.record&.errors&.of_kind?(:slot_number, :taken)
        next
      end
    end

    if slot.nil?
      slots = @session.save_slots.order(:slot_number).map { |s| slot_payload(s) }
      return render json: { error: "all_slots_full", slots: slots }, status: :conflict
    end

    @session.update_column(:active_save_slot, slot.slot_number)
    render json: slot_payload(slot), status: :created
  end

  # PATCH /emulator/save_slots/:slot_number — overwrite specific slot.
  # Used for the explicit-overwrite path after 409 on create. The bytes the
  # client sends here are a fresh `getSaveFile()` snapshot, NOT the original
  # 409-triggering payload — there may be a few seconds of in-game drift.
  # Project Owner accepts this tradeoff for stateless overwrite handling.
  def update
    return head :not_found if @session.nil? || @slot.nil?
    return head :content_too_large if oversized?
    bytes = read_body
    return head :content_too_large if bytes.bytesize > MAX_SAVE_DATA_BYTES
    return invalid_save_response unless valid_sram?(bytes)

    @slot.update!(save_data: bytes)
    @session.update_column(:active_save_slot, @slot.slot_number)
    render json: slot_payload(@slot)
  end

  # DELETE /emulator/save_slots/:slot_number — wipe a single slot.
  # If the slot was active, also clear `active_save_slot` so the next page
  # load resolves to "no save" rather than dangling against a deleted slot.
  def destroy
    return head :not_found if @session.nil? || @slot.nil?
    was_active = @session.active_save_slot == @slot.slot_number
    @slot.destroy!
    @session.update_column(:active_save_slot, nil) if was_active
    head :no_content
  end

  # POST /emulator/save_slots/:slot_number/restore — pointer change only.
  # Sets `active_save_slot` to this slot's number. NO byte mutation; the
  # other 4 slots stay intact. Player must hard-refresh for the emulator to
  # boot from the new active slot.
  def restore
    return head :not_found if @session.nil? || @slot.nil?
    @session.update_column(:active_save_slot, @slot.slot_number)
    head :no_content
  end

  # GET /emulator/save_slots/:slot_number/download — .sav download for one
  # slot. Returns 204 when the slot has no bytes (shouldn't happen in
  # practice — empty slots are deleted, not retained — but defensive).
  def download
    return head :not_found if @session.nil? || @slot.nil?
    return head :no_content if @slot.save_data.blank?
    send_data @slot.save_data,
              type: "application/octet-stream",
              disposition: "attachment",
              filename: "pokemon-platinum-slot#{@slot.slot_number}.sav"
  end

  private

  def slot_payload(slot)
    raw = slot.read_attribute_before_type_cast("save_data")
    # On freshly-created records, AR can hand back an ActiveModel::Type::
    # Binary::Data wrapper rather than a plain String — call `.to_s` to
    # normalize before measuring. Reloaded records already return a String.
    saved_bytes = raw.respond_to?(:to_s) ? raw.to_s.bytesize : nil
    {
      slot_number: slot.slot_number,
      parsed_trainer_name: slot.parsed_trainer_name,
      parsed_money: slot.parsed_money,
      parsed_play_seconds: slot.parsed_play_seconds,
      parsed_badges: slot.parsed_badges,
      parsed_map_id: slot.parsed_map_id,
      updated_at: slot.updated_at,
      saved_bytes: raw.nil? ? nil : saved_bytes
    }
  end

  # Resolves the current player's own session for the active run. Returns
  # nil when there is no active run or the player has not claimed a session
  # — both surface as 404 to the caller, regardless of which slot was
  # requested. This is the authorization gate for every slot action.
  def set_session
    run = SoulLinkRun.current(session[:guild_id])
    @session = run&.soul_link_emulator_sessions&.find_by(discord_user_id: current_user_id)
  end

  def set_slot
    @slot = @session&.save_slots&.find_by(slot_number: params[:slot_number])
  end

  def oversized?
    request.content_length && request.content_length > MAX_SAVE_DATA_BYTES
  end

  def read_body
    request.body.read
  end

  # Reject any payload that the parser can't read. Catches:
  #   - wrong total size (real Platinum SRAM is exactly 0x80000 bytes)
  #   - both general-block CRCs failing (every byte got corrupted, or
  #     bytes that aren't a Platinum save at all)
  # Run synchronously here so the player gets immediate 422 feedback rather
  # than a silent "save succeeded but parse_job logged a CRC fail" mystery.
  # The parser is a pure function — sub-millisecond on a 512KB buffer.
  def valid_sram?(bytes)
    SoulLink::SaveParser.parse(bytes) ? true : false
  end

  def invalid_save_response
    render json: { error: "invalid_save_data" }, status: :unprocessable_content
  end
end
