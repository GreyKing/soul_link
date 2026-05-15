require "test_helper"

class RunsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @run = create(:soul_link_run, guild_id: LoginHelper::GUILD_ID)
    login_as(153665622641737728)
  end

  test "GET /runs/:id/edit returns the template editor form" do
    get edit_run_path(@run)
    assert_response :success
    assert_select "form[action=?]", run_path(@run)
    assert_select "select[name='soul_link_run[timezone]']"
  end

  test "PATCH /runs/:id updates schedule_template and timezone" do
    template = { "slots" => [ { "day_of_week" => 1, "time_of_day" => "19:00" } ] }
    patch run_path(@run), params: {
      soul_link_run: { timezone: "America/Los_Angeles", schedule_template: template.to_json }
    }
    assert_redirected_to edit_run_path(@run)
    @run.reload
    assert_equal "America/Los_Angeles", @run.timezone
    assert_equal 1, @run.schedule_template["slots"].length
  end

  test "PATCH /runs/:id rejects malformed template" do
    bad = { "slots" => [ { "day_of_week" => 99, "time_of_day" => "19:00" } ] }
    patch run_path(@run), params: {
      soul_link_run: { timezone: "America/Phoenix", schedule_template: bad.to_json }
    }
    assert_response :unprocessable_entity
    @run.reload
    assert_nil @run.schedule_template
  end
end
