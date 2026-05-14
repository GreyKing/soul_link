require "test_helper"

class GymPollTest < ActiveSupport::TestCase
  test "factory builds a valid open poll" do
    poll = build(:gym_poll)
    assert poll.valid?, poll.errors.full_messages.inspect
    assert_equal "open", poll.status
  end

  test "status must be open or locked" do
    poll = build(:gym_poll, status: "bogus")
    refute poll.valid?
    assert_includes poll.errors[:status], "is not included in the list"
  end

  test "open? and locked? helpers" do
    open_poll   = build(:gym_poll)
    locked_poll = build(:gym_poll, :locked)
    assert open_poll.open?
    refute open_poll.locked?
    assert locked_poll.locked?
    refute locked_poll.open?
  end
end
