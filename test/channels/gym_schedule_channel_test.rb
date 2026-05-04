require "test_helper"

# Step 20 — proposer-only authz on the cancel action. The view hides the
# Cancel button for non-proposers (gym_schedules/show.html.erb), but a
# determined user could still hand-craft a WebSocket message; the channel
# enforces the same rule server-side.
class GymScheduleChannelTest < ActionCable::Channel::TestCase
  GREY  = 153665622641737728   # proposer in these tests
  ARATY = 600802903967531093   # non-proposer

  setup do
    @run = create(:soul_link_run)
    @schedule = create(:gym_schedule, soul_link_run: @run, proposed_by: GREY)
  end

  test "subscribes and streams for the schedule" do
    stub_connection(current_user_id: GREY)
    subscribe(schedule_id: @schedule.id)
    assert subscription.confirmed?
    assert_has_stream_for @schedule
  end

  test "proposer can cancel the schedule" do
    stub_connection(current_user_id: GREY)
    subscribe(schedule_id: @schedule.id)

    perform :cancel
    @schedule.reload
    assert @schedule.cancelled?, "schedule should be cancelled by the proposer"
  end

  test "non-proposer's cancel is rejected and schedule stays active" do
    stub_connection(current_user_id: ARATY)
    subscribe(schedule_id: @schedule.id)

    perform :cancel
    @schedule.reload
    refute @schedule.cancelled?, "schedule should NOT be cancelled by a non-proposer"
    assert @schedule.proposed?, "schedule should still be in its original state"

    # The channel should have transmitted an error to the requesting user.
    assert_match(
      /Only the proposer can cancel/,
      transmissions.map { |t| t["error"] }.compact.join(" "),
      "expected an error transmission explaining proposer-only"
    )
  end

  test "non-proposer cannot trigger broadcast_state via cancel" do
    stub_connection(current_user_id: ARATY)
    subscribe(schedule_id: @schedule.id)

    # subscribe() always broadcasts initial state once. After that, a
    # rejected cancel should NOT trigger a second broadcast.
    initial_broadcasts = broadcasts(@schedule).size
    perform :cancel
    final_broadcasts = broadcasts(@schedule).size

    assert_equal initial_broadcasts, final_broadcasts, "rejected cancel should not broadcast"
  end
end
