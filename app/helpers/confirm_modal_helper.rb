module ConfirmModalHelper
  # Renders the shared confirm-modal partial. Pair with a trigger button
  # carrying `data-action="click->confirm-modal#open"` and
  # `data-confirm-modal-id-param="<id>"`.
  #
  # @param id [String] DOM id; must match the trigger's id-param.
  # @param title [String] uppercase short label shown in the modal title row.
  # @param body [String] HTML-safe body copy explaining the consequence.
  # @param confirm_label [String] uppercase short label for the destructive button.
  # @param confirm_class [String] CSS class for the destructive button (default gb-btn-danger gb-btn-sm).
  # @param confirm_data [Hash] hash of data-* attributes spread onto the destructive button — this is where the original Stimulus action goes (e.g. `{ action: "click->run-management#endRun" }`).
  # @param cancel_label [String] uppercase short label for the safe-default button (default CANCEL).
  def confirm_modal(id:, title:, body:, confirm_label:, confirm_class: "gb-btn-danger gb-btn-sm", confirm_data: {}, cancel_label: "CANCEL")
    render(
      "shared/confirm_modal",
      id: id,
      title: title,
      body: body,
      confirm_label: confirm_label,
      confirm_class: confirm_class,
      confirm_data: confirm_data,
      cancel_label: cancel_label
    )
  end
end
