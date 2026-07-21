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

    test "every ability has a non-empty short and full effect entry" do
      missing = []
      SoulLink::GameState.all_abilities.each do |name|
        effect = SoulLink::GameState.ability_effect(name)
        if effect.nil? || effect["short"].to_s.strip.empty? || effect["full"].to_s.strip.empty?
          missing << name
        end
      end
      assert_empty missing, "abilities missing short/full effect: #{missing.join(', ')}"
    end
  end
end
