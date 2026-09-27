require "test_helper"

# Jobs must live in the primary database so they survive a restart and any
# process (Puma, the Discord bot, the jobs worker) can enqueue them. The
# adapter is called directly because ActiveJob::TestHelper swaps every job
# class onto the test adapter.
class SolidQueueAdapterTest < ActiveSupport::TestCase
  class ProbeJob < ApplicationJob
    cattr_accessor :performed_with

    def perform(run, note)
      self.class.performed_with = [ run, note ]
    end
  end

  test "Solid Queue uses the primary database" do
    assert_equal ActiveRecord::Base.connection_db_config, SolidQueue::Record.connection_db_config
  end

  test "an enqueued job is stored in the database and runs from what was stored" do
    run = create(:soul_link_run)
    job = ProbeJob.new(run, "hello")

    assert_difference -> { SolidQueue::Job.count } => 1, -> { SolidQueue::ReadyExecution.count } => 1 do
      ActiveJob::QueueAdapters::SolidQueueAdapter.new.enqueue(job)
    end

    stored = SolidQueue::Job.find_by!(active_job_id: job.job_id)
    assert_equal ProbeJob.name, stored.class_name

    ProbeJob.performed_with = nil
    ActiveJob::Base.execute(stored.arguments)
    assert_equal [ run, "hello" ], ProbeJob.performed_with
  end
end
