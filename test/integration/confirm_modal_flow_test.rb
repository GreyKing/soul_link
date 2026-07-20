require "test_helper"

# Step 20 — integration test for the shared confirm-modal partial wired
# behind a destructive action. Verifies the END RUN trigger on /runs no
# longer fires the action directly; instead it opens the confirm modal
# whose CONFIRM button carries the original Stimulus action.
#
# We can't drive Stimulus interactively from an integration test (that
# would need a system test with Selenium); but we CAN verify that the
# rendered markup carries the correct wiring, which is what the architect
# brief locks down.
class ConfirmModalFlowTest < ActionDispatch::IntegrationTest
  GREY = 153665622641737728

  setup do
    @run = create(:soul_link_run)
    login_as(GREY)
  end

  # ── Trigger scoping ────────────────────────────────────────────────────
  #
  # Stimulus routes an action to the CLOSEST ANCESTOR element carrying that
  # controller. A trigger rendered as a *sibling* of its modal therefore has
  # no controller to route to and silently does nothing — the modal can never
  # open, and the destructive action behind it becomes unreachable.
  #
  # That is exactly what shipped: both call sites rendered the trigger beside
  # the modal, and every existing test passed because they asserted that the
  # trigger and the modal each existed, never that they were connected.
  #
  # This assertion checks the relationship rather than the parts, so it holds
  # for any future call site without needing to be extended.
  def assert_every_trigger_is_scoped(body, page:)
    doc = Nokogiri::HTML(body)
    triggers = doc.css('[data-action*="confirm-modal#open"]')

    assert_predicate triggers, :any?, "expected at least one confirm-modal trigger on #{page}"

    triggers.each do |trigger|
      scoped = trigger.ancestors.any? do |node|
        node["data-controller"].to_s.split(/\s+/).include?("confirm-modal")
      end

      assert scoped,
             "a confirm-modal trigger on #{page} has no confirm-modal controller ancestor, " \
             "so Stimulus can never route its click and the modal is unreachable"
    end
  end

  test "every END RUN trigger on the dashboard is inside a confirm-modal controller" do
    get root_path
    assert_response :success

    assert_every_trigger_is_scoped(response.body, page: "the dashboard RUNS tab")
  end

  test "every DEL trigger on the species page is inside a confirm-modal controller" do
    group = create(:soul_link_pokemon_group, soul_link_run: @run)
    create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: group,
           discord_user_id: GREY, species: "Staravia")

    get species_path
    assert_response :success

    assert_every_trigger_is_scoped(response.body, page: "the species assignment page")
  end

  # Step 24 R1 — `/runs` is now a 301 redirect to the canonical
  # dashboard RUNS tab. The legacy `End Current Run` page modal is
  # gone; the dashboard's `End Run` modal (id `end-run-dashboard-confirm`)
  # is the canonical surface and the next test covers it.
  test "/runs redirects to root_path with #runs anchor" do
    get runs_path
    assert_response :moved_permanently
    assert_equal "http://www.example.com/#runs", response.redirect_url
  end

  test "dashboard RUNS tab END RUN button opens the confirm modal instead of firing endRun directly" do
    get root_path
    assert_response :success

    # The trigger button no longer carries the direct end-run action.
    assert_no_match(/<button[^>]*data-action="click->run-management#endRun"[^>]*>\s*END RUN/m, response.body)

    # Instead it opens the confirm modal — and does so from inside the
    # controller element, which is what makes the action reachable at all.
    scope = Nokogiri::HTML(response.body).at_css('[data-controller~="confirm-modal"]')
    refute_nil scope
    refute_nil scope.at_css('button[data-action*="confirm-modal#open"]')
    refute_nil scope.at_css("#end-run-dashboard-confirm")
  end

  test "dashboard RUNS tab renders the END RUN confirm modal with correct ARIA wiring" do
    get root_path
    assert_response :success

    # Modal container with id matching the trigger's id-param.
    assert_match(/id="end-run-dashboard-confirm"/, response.body)

    # role="dialog" + aria-modal + aria-labelledby pointing at the title.
    assert_match(/role="dialog"/, response.body)
    assert_match(/aria-modal="true"/, response.body)
    assert_match(/aria-labelledby="end-run-dashboard-confirm-title"/, response.body)
    assert_match(/id="end-run-dashboard-confirm-title">END THIS RUN\?/, response.body)
  end

  test "dashboard RUNS tab confirm button carries the original endRun action" do
    get root_path
    assert_response :success

    # The confirm button inside the modal is the only place that still
    # carries data-action="click->run-management#endRun".
    assert_match(/data-action="click-&gt;run-management#endRun"/, response.body)

    # And it lives inside a button with the destructive class.
    assert_match(
      /<button[^>]*class="gb-btn-danger gb-btn-sm"[^>]*data-action="click-&gt;run-management#endRun"[^>]*>\s*END RUN/m,
      response.body
    )
  end

  test "dashboard RUNS tab END RUN trigger uses a distinct modal id from /runs" do
    get root_path
    assert_response :success

    # When viewing the dashboard, the dashboard runs tab uses
    # `end-run-dashboard-confirm` so it doesn't collide with the /runs page
    # if a future redesign hosts both surfaces in one tree. The id now lives
    # only on the dialog — the trigger no longer needs an id-param, because
    # scoping alone determines which dialog it opens.
    assert_match(/id="end-run-dashboard-confirm"/, response.body)
    assert_equal 1, Nokogiri::HTML(response.body).css("#end-run-dashboard-confirm").length,
                 "the dialog id must be unique on the page"
  end
end
