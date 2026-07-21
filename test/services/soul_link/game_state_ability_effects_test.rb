require "test_helper"

module SoulLink
  class GameStateAbilityEffectsTest < ActiveSupport::TestCase
    test "ability_effect returns short and full for a known ability" do
      effect = SoulLink::GameState.ability_effect("Levitate")
      assert_equal "Immune to Ground", effect["short"]
      assert_equal "Gives full immunity to all Ground-type moves.", effect["full"]
    end

    test "ability_effect returns nil for an unknown ability" do
      assert_nil SoulLink::GameState.ability_effect("Not An Ability")
    end

    test "ability_effects is a non-empty hash keyed by ability name" do
      assert SoulLink::GameState.ability_effects.is_a?(Hash)
      assert SoulLink::GameState.ability_effects.key?("Static")
    end
  end
end
