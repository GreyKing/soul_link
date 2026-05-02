require "test_helper"

module SoulLink
  class SaveDiffTest < ActiveSupport::TestCase
    test "nil prev returns empty result" do
      result = SoulLink::SaveDiff.between(prev_badges: nil, curr_badges: 5)
      assert_kind_of SoulLink::SaveDiff::Result, result
      assert_equal [], result.badge_events
      assert result.empty?
    end

    test "nil curr returns empty result" do
      result = SoulLink::SaveDiff.between(prev_badges: 3, curr_badges: nil)
      assert_equal [], result.badge_events
      assert result.empty?
    end

    test "equal values return empty result" do
      result = SoulLink::SaveDiff.between(prev_badges: 3, curr_badges: 3)
      assert_equal [], result.badge_events
      assert result.empty?
    end

    test "+1 badge produces one BadgeGained event" do
      result = SoulLink::SaveDiff.between(prev_badges: 3, curr_badges: 4)
      assert_equal 1, result.badge_events.size
      event = result.badge_events.first
      assert_kind_of SoulLink::SaveDiff::BadgeGained, event
      assert_equal 4, event.gym_number
    end

    test "+2 badges produces two BadgeGained events in sequential order" do
      result = SoulLink::SaveDiff.between(prev_badges: 3, curr_badges: 5)
      assert_equal 2, result.badge_events.size
      assert(result.badge_events.all? { |e| e.is_a?(SoulLink::SaveDiff::BadgeGained) })
      assert_equal [ 4, 5 ], result.badge_events.map(&:gym_number)
    end

    test "-1 badge produces one BadgeLost event" do
      result = SoulLink::SaveDiff.between(prev_badges: 5, curr_badges: 4)
      assert_equal 1, result.badge_events.size
      event = result.badge_events.first
      assert_kind_of SoulLink::SaveDiff::BadgeLost, event
      assert_equal 5, event.gym_number
    end

    test "full reset prev=8 curr=0 produces 8 BadgeLost events" do
      result = SoulLink::SaveDiff.between(prev_badges: 8, curr_badges: 0)
      assert_equal 8, result.badge_events.size
      assert(result.badge_events.all? { |e| e.is_a?(SoulLink::SaveDiff::BadgeLost) })
      assert_equal (1..8).to_a, result.badge_events.map(&:gym_number)
    end

    test "full claim prev=0 curr=8 produces 8 BadgeGained events" do
      result = SoulLink::SaveDiff.between(prev_badges: 0, curr_badges: 8)
      assert_equal 8, result.badge_events.size
      assert(result.badge_events.all? { |e| e.is_a?(SoulLink::SaveDiff::BadgeGained) })
      assert_equal (1..8).to_a, result.badge_events.map(&:gym_number)
    end
  end
end
