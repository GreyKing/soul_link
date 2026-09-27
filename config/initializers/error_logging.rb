# Rails.error has no subscribers by default, so errors reported from
# background threads would vanish. Examples are a failed Solid Cable write on
# its writer thread, or a Solid Queue supervisor or worker thread error.
# Log them.
class ErrorLogSubscriber
  def report(error, handled:, severity:, context:, source: nil)
    level = severity == :warning ? :warn : severity
    backtrace = Array(error.backtrace).first(10).join("\n")
    Rails.logger.public_send(level, "[#{source}] #{error.class}: #{error.message}\n#{backtrace}".strip)
  end
end

Rails.error.subscribe(ErrorLogSubscriber.new)
