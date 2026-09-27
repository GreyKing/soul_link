require "test_helper"

# Background threads (the Solid Cable writer, Solid Queue's supervisor
# threads) report failures through Rails.error instead of raising. Without a
# subscriber those reports would vanish.
class ErrorLoggingTest < ActiveSupport::TestCase
  test "errors reported to Rails.error are written to the log" do
    original = Rails.logger
    log = StringIO.new
    Rails.logger = ActiveSupport::Logger.new(log)

    Rails.error.report(RuntimeError.new("writer boom"), handled: true)

    assert_match(/\[application\] RuntimeError: writer boom/, log.string)
  ensure
    Rails.logger = original
  end
end
