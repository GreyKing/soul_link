module ConfirmModalHelper
  # Renders the shared confirm-modal partial, wrapping the caller's trigger
  # and the dialog in a single `confirm-modal` controller element.
  #
  # The trigger MUST be passed as a block rather than written beside the
  # call. Stimulus routes an action to the closest ancestor element carrying
  # that controller, so a trigger rendered as a *sibling* of the dialog has
  # nothing to route to: the click is silently dropped and the dialog can
  # never open. Owning the wrapper here is what makes that arrangement
  # impossible to express.
  #
  #   <%= confirm_modal(id: "end-run-confirm", ...) do %>
  #     <button data-action="click->confirm-modal#open"
  #             class="gb-btn-danger gb-btn-sm">END RUN</button>
  #   <% end %>
  #
  # @param id [String] DOM id for the dialog, also used for aria-labelledby.
  # @param title [String] uppercase short label shown in the modal title row.
  # @param body [String] HTML-safe body copy explaining the consequence.
  # @param confirm_label [String] uppercase short label for the destructive button.
  # @param confirm_class [String] CSS class for the destructive button (default gb-btn-danger gb-btn-sm).
  # @param confirm_data [Hash] hash of data-* attributes spread onto the destructive button — this is where the original Stimulus action goes (e.g. `{ action: "click->run-management#endRun" }`).
  # @param cancel_label [String] uppercase short label for the safe-default button (default CANCEL).
  # @yield the trigger markup, rendered inside the controller element.
  def confirm_modal(id:, title:, body:, confirm_label:, confirm_class: "gb-btn-danger gb-btn-sm", confirm_data: {}, cancel_label: "CANCEL", &trigger)
    unless trigger
      raise ArgumentError,
            "confirm_modal requires a trigger block — the trigger must render inside the " \
            "controller element or Stimulus cannot route its click to #open"
    end

    render(
      "shared/confirm_modal",
      id: id,
      title: title,
      body: body,
      confirm_label: confirm_label,
      confirm_class: confirm_class,
      confirm_data: confirm_data,
      cancel_label: cancel_label,
      trigger: capture(&trigger)
    )
  end
end
