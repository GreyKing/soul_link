require "test_helper"

# Step 19 — end-to-end wipe flow. Set up a run where Mark Dead leaves one
# player at 0 alive; PATCH the group to dead; assert wiped_at is set,
# `notify_wipe` fires (stubbed), and the dashboard re-render carries the
# read-only banner.
class WipeFlowTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728
  ARATY = 600802903967531093
  SCYTHE = 189518174125817856
  ZEAL = 182742127061630976

  setup do
    @run = create(:soul_link_run)
  end

  test "PATCH pokemon_group with status=dead triggers wipe + notify_wipe + read-only banner" do
    # One alive group linking TWO players' Pokemon (Grey + ARaty) — this
    # is each of their only catch in the run, so when the group flips
    # dead the wipe rule (player has catches AND zero alive) fires for
    # both, but WipeCoordinator reports the first player in canonical
    # `player_ids` order, which is Grey. The two linked Pokemon also let
    # the death-notification assertion below actually constrain the
    # controller call site: a single grouped message is still expected
    # even though more than one Pokemon died.
    group = create(:soul_link_pokemon_group, soul_link_run: @run, status: "caught", nickname: "DOOMED", location: "Route 207")
    create(:soul_link_pokemon,
           soul_link_run: @run,
           soul_link_pokemon_group: group,
           discord_user_id: GREY,
           species: "Bidoof",
           name: "DOOMED",
           location: "Route 207",
           status: "caught")
    create(:soul_link_pokemon,
           soul_link_run: @run,
           soul_link_pokemon_group: group,
           discord_user_id: ARATY,
           species: "Shinx",
           name: "DOOMED",
           location: "Route 207",
           status: "caught")

    login_as(GREY)

    wipe_calls = []
    death_calls = []
    wipe_recorder = ->(run, uid, route) { wipe_calls << { run_id: run.id, uid: uid, route: route } }
    death_recorder = ->(*) { death_calls << :hit }

    SoulLink::DiscordNotifier.stub(:notify_wipe, wipe_recorder) do
      SoulLink::DeathMessage.stub(:post_or_update, death_recorder) do
        patch pokemon_group_path(group), params: { status: "dead" }, as: :json
      end
    end

    assert_response :success
    @run.reload
    assert @run.wiped_at.present?, "wiped_at should be set after Mark Dead"
    assert @run.read_only?, "run should be in read-only mode after wipe"

    assert_equal 1, wipe_calls.size
    assert_equal GREY, wipe_calls.first[:uid]
    assert_equal "Route 207", wipe_calls.first[:route]

    assert_equal 1, death_calls.size, "one death notification per group, not one per linked Pokemon"

    # Re-render the dashboard — the wipe banner should appear above
    # the gb-grid-4 stats in the runs panel, and at least one of the
    # gated affordances should be absent. We pick "+ NEW CATCH" (the
    # PC-box modal trigger) because it sits on the default tab and
    # therefore renders unconditionally on a healthy dashboard.
    get root_path
    assert_response :success
    assert_match(/RUN ENDED/, response.body)
    assert_no_match(/\+ NEW CATCH/, response.body)
  end

  test "PATCH pokemon_group with status=dead does NOT trigger wipe when every player still has at least one alive" do
    # Each of the 4 players has TWO alive catches. We mark ONE of Grey's
    # groups dead — Grey still has 1 alive, so no wipe should fire.
    [ GREY, ARATY, SCYTHE, ZEAL ].each_with_index do |uid, i|
      2.times do |j|
        g = create(:soul_link_pokemon_group, soul_link_run: @run, status: "caught",
                   nickname: "G#{i}-#{j}", location: "Route 20#{i}")
        create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: g,
               discord_user_id: uid, species: "Bidoof", name: "G#{i}-#{j}",
               location: "Route 20#{i}", status: "caught")
      end
    end

    grey_first_group = @run.soul_link_pokemon_groups.joins(:soul_link_pokemon)
                            .where(soul_link_pokemon: { discord_user_id: GREY })
                            .order(:position).first

    login_as(GREY)
    wipe_calls = []
    SoulLink::DiscordNotifier.stub(:notify_wipe, ->(*) { wipe_calls << :hit }) do
      SoulLink::DeathMessage.stub(:post_or_update, ->(*) { }) do
        patch pokemon_group_path(grey_first_group), params: { status: "dead" }, as: :json
      end
    end

    assert_response :success
    assert_nil @run.reload.wiped_at, "wiped_at stays nil — every player still has at least one alive"
    assert_equal [], wipe_calls
  end
end
