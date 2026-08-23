require "test_helper"
require "rake"

class GymResultBackfillTaskTest < ActiveSupport::TestCase
  TASK_NAME = "soul_link:backfill_gym_result_draft".freeze

  @loaded = false
  class << self
    attr_accessor :loaded
  end

  setup do
    unless self.class.loaded
      Rails.application.load_tasks
      self.class.loaded = true
    end
    Rake::Task[TASK_NAME].reenable

    @run = create(:soul_link_run)
    @group = create(:soul_link_pokemon_group, :route201, soul_link_run: @run)
    create(:soul_link_pokemon, :route201_grey, soul_link_run: @run, soul_link_pokemon_group: @group)
    @draft = create(:gym_draft, soul_link_run: @run, status: "complete",
      state_data: { "ready_players" => [], "first_pick_votes" => {},
                    "picks" => [ { "round" => 1, "group_id" => @group.id, "picked_by" => 1 } ] })
  end

  def invoke
    capture_io { Rake::Task[TASK_NAME].invoke }
  end

  test "attaches the pending draft to the most recent draftless gym result" do
    @run.gym_results.create!(gym_number: 1, beaten_at: 2.days.ago)
    latest = @run.gym_results.create!(gym_number: 2, beaten_at: 1.day.ago)

    invoke

    assert_equal @draft, latest.reload.gym_draft
    assert_equal [ @group.id ], latest.team_snapshot["groups"].map { |g| g["group_id"] }
    assert_nil @run.gym_results.find_by(gym_number: 1).gym_draft
  end

  test "is a no-op when the latest result already has a draft" do
    @run.gym_results.create!(gym_number: 1, beaten_at: Time.current, gym_draft: @draft)

    invoke

    assert_equal 1, @run.gym_results.count
    assert_equal @draft, @run.gym_results.first.reload.gym_draft
  end

  test "DRY_RUN makes no changes" do
    result = @run.gym_results.create!(gym_number: 1, beaten_at: Time.current)

    ENV["DRY_RUN"] = "1"
    invoke
    ENV.delete("DRY_RUN")

    assert_nil result.reload.gym_draft
  end
end
