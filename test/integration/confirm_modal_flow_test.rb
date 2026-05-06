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

    # Instead, it opens the confirm modal.
    assert_match(/data-action="click->confirm-modal#open"[^>]*data-confirm-modal-id-param="end-run-dashboard-confirm"/m, response.body)
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
    # if a future redesign hosts both surfaces in one tree.
    assert_match(/data-confirm-modal-id-param="end-run-dashboard-confirm"/, response.body)
    assert_match(/id="end-run-dashboard-confirm"/, response.body)
  end
end
