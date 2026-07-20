require "test_helper"

# Step 20 — unit tests for ConfirmModalHelper#confirm_modal.
# Asserts the rendered partial carries the right ARIA wiring + spreads
# `confirm_data` onto the confirm button as data-* attributes.
class ConfirmModalHelperTest < ActionView::TestCase
  include ConfirmModalHelper

  # `confirm_modal` now REQUIRES a trigger block — the trigger and the dialog
  # must render inside one controller element or Stimulus can never route the
  # open action. Most tests below only care about the dialog's contents, so
  # they go through this shim rather than repeating a throwaway trigger.
  def render_confirm_modal(**kwargs, &trigger)
    trigger ||= -> { tag.button("GO", data: { action: "click->confirm-modal#open" }) }
    confirm_modal(**kwargs, &trigger)
  end

  # ── Trigger/dialog scoping — the invariant that was previously unenforced ──

  test "raises without a trigger block so miswiring fails loudly at render time" do
    error = assert_raises(ArgumentError) do
      confirm_modal(id: "x", title: "Y?", body: "Z.", confirm_label: "GO", confirm_data: {})
    end

    assert_match(/trigger block/i, error.message)
  end

  test "renders the trigger and the dialog inside one confirm-modal controller element" do
    html = render_confirm_modal(id: "scoped", title: "Y?", body: "Z.", confirm_label: "GO", confirm_data: {}) do
      tag.button("TRIGGER ME", data: { action: "click->confirm-modal#open" })
    end

    scope = Nokogiri::HTML::DocumentFragment.parse(html).at_css('[data-controller~="confirm-modal"]')
    refute_nil scope, "expected a confirm-modal controller element"

    refute_nil scope.at_css('button[data-action*="confirm-modal#open"]'),
               "the trigger must render INSIDE the controller element — Stimulus routes actions to " \
               "the closest ancestor controller, so a sibling trigger silently never fires"
    refute_nil scope.at_css("#scoped"),
               "the dialog must render inside the same controller element as its trigger"
  end

  test "renders all required locals" do
    html = render_confirm_modal(
      id: "test-confirm",
      title: "DELETE WIDGET?",
      body: "This removes the widget.",
      confirm_label: "DELETE WIDGET",
      confirm_data: { action: "click->widget#destroy" }
    )

    assert_includes html, "DELETE WIDGET?"
    assert_includes html, "This removes the widget."
    assert_includes html, "DELETE WIDGET"
  end

  test "outer container has correct ARIA wiring" do
    html = render_confirm_modal(
      id: "end-run-confirm",
      title: "END THIS RUN?",
      body: "Body copy.",
      confirm_label: "END RUN",
      confirm_data: { action: "click->run-management#endRun" }
    )

    assert_match(/role="dialog"/, html)
    assert_match(/aria-modal="true"/, html)
    assert_match(/aria-labelledby="end-run-confirm-title"/, html)
    assert_match(/id="end-run-confirm-title"/, html)
  end

  test "outer wrapper has the partial id" do
    html = render_confirm_modal(
      id: "my-special-id",
      title: "X?",
      body: "Y.",
      confirm_label: "Z",
      confirm_data: {}
    )

    assert_match(/id="my-special-id"/, html)
  end

  test "data-controller attaches confirm-modal" do
    html = render_confirm_modal(
      id: "any",
      title: "X?",
      body: "Y.",
      confirm_label: "Z",
      confirm_data: {}
    )

    assert_match(/data-controller="confirm-modal"/, html)

    # The dialog is reached through a target rather than an id value: one
    # controller instance now owns exactly one trigger/dialog pair, so there
    # is no id to disambiguate on.
    assert_match(/data-confirm-modal-target="dialog"/, html)
    assert_match(/id="any"/, html)
  end

  test "confirm_data hash spreads as data-* attributes on the confirm button" do
    html = render_confirm_modal(
      id: "delete-slot-3-confirm",
      title: "DELETE THIS SLOT?",
      body: "Body.",
      confirm_label: "DELETE FOREVER",
      confirm_data: { action: "click->save-slots#deleteSlot", slot_number: 3 }
    )

    assert_match(/data-action="click-&gt;save-slots#deleteSlot"/, html)
    assert_match(/data-slot-number="3"/, html)
  end

  test "confirm_class defaults to gb-btn-danger gb-btn-sm" do
    html = render_confirm_modal(
      id: "x",
      title: "Y?",
      body: "Z.",
      confirm_label: "DESTROY",
      confirm_data: {}
    )

    # Confirm button uses the default class.
    assert_match(/class="gb-btn-danger gb-btn-sm"/, html)
  end

  test "confirm_class can be overridden" do
    html = render_confirm_modal(
      id: "x",
      title: "Y?",
      body: "Z.",
      confirm_label: "DESTROY",
      confirm_class: "custom-confirm-class",
      confirm_data: {}
    )

    assert_match(/class="custom-confirm-class"/, html)
  end

  test "body accepts safe HTML such as <strong>" do
    html = render_confirm_modal(
      id: "x",
      title: "Y?",
      body: "This action <strong>cannot be undone</strong>.",
      confirm_label: "GO",
      confirm_data: {}
    )

    # Should contain a literal <strong> tag, not the HTML-escaped form.
    assert_includes html, "<strong>cannot be undone</strong>"
  end

  test "cancel_label defaults to CANCEL" do
    html = render_confirm_modal(
      id: "x",
      title: "Y?",
      body: "Z.",
      confirm_label: "GO",
      confirm_data: {}
    )

    # Cancel button content is whitespace-padded inside <button>...</button>.
    assert_match(/>\s*CANCEL\s*</, html)
  end

  test "cancel_label can be overridden" do
    html = render_confirm_modal(
      id: "x",
      title: "Y?",
      body: "Z.",
      confirm_label: "GO",
      confirm_data: {},
      cancel_label: "BACK OUT"
    )

    assert_match(/>\s*BACK OUT\s*</, html)
  end

  test "modal starts hidden" do
    html = render_confirm_modal(
      id: "x",
      title: "Y?",
      body: "Z.",
      confirm_label: "GO",
      confirm_data: {}
    )

    assert_match(/class="hidden"/, html)
  end
end
