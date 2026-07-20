require "test_helper"

# Markup-assertion test for dragging a PC-box Pokemon into the party.
#
# The load-bearing assertion is the seven `data-group-*` attributes on a
# rendered `.team-slot`. `pixeldex#selectPokemon → #openModal` reads all
# seven; if a future edit drops any of them the detail modal opens blank,
# and because `data-group-id` is still present, pressing SAVE writes that
# blank state back to a real group. Silent data loss — hence the guard.
class PartyDragTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728

  setup do
    @run = create(:soul_link_run)
    login_as(GREY)
  end

  test "the dashboard keeps its existing Stimulus controllers and adds party-drag" do
    get root_path
    assert_response :success

    controllers = response.body[/data-controller="([^"]*\bparty-drag\b[^"]*)"/, 1]
    assert controllers, "expected a data-controller list containing party-drag"

    %w[dashboard pixeldex run-management party-drag].each do |name|
      assert_includes controllers.split, name,
        "party-drag must be appended to the existing controller list, not replace it"
    end
  end

  test "the box grid and party panel expose their party-drag targets" do
    get root_path
    assert_response :success

    assert_match(/data-party-drag-target="boxGrid"/, response.body)
    assert_match(/data-party-drag-target="partyList"/, response.body)
    assert_match(/data-party-drag-update-url-value="#{Regexp.escape(update_slots_team_path)}"/, response.body)
  end

  test "box cells carry data-alive so dead Pokemon cannot be dragged" do
    seed_party

    get root_path
    assert_response :success

    assert_match(/data-alive="true"/, response.body)
    assert_match(/data-alive="false"/, response.body)
  end

  test "a rendered party slot carries all seven data-group-* attributes" do
    seed_party

    get root_path
    assert_response :success

    # Anchored on the slot-number child rather than the closing `>` of the
    # opening tag, because `click->pixeldex#selectPokemon` contains a `>`.
    slot = response.body[/<div class="team-slot"(.*?)<div class="team-slot-num"/m, 1]
    assert slot, "expected at least one rendered .team-slot"

    %w[
      data-group-id
      data-group-nickname
      data-group-species
      data-group-location
      data-group-status
      data-group-types
      data-group-pokemon
    ].each do |attribute|
      assert_includes slot, attribute,
        "#{attribute} is read by pixeldex#openModal; dropping it blanks the detail modal"
    end

    assert_includes slot, "click->pixeldex#selectPokemon"
  end

  private

  # One living party member (in a team slot) plus one dead group, so the
  # `data-alive` true/false assertions both have something to match.
  def seed_party
    alive = create(:soul_link_pokemon_group, :route201, soul_link_run: @run)
    create(:soul_link_pokemon, :route201_grey, soul_link_run: @run, soul_link_pokemon_group: alive)

    dead = create(:soul_link_pokemon_group, :route202, soul_link_run: @run, status: "dead")
    create(:soul_link_pokemon, :route202_grey, soul_link_run: @run, soul_link_pokemon_group: dead)

    team = create(:soul_link_team, :grey_team, soul_link_run: @run)
    create(:soul_link_team_slot, :slot_1,
      soul_link_team: team, soul_link_pokemon_group: alive)
  end
end
