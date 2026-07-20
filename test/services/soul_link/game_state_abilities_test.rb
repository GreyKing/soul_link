require "test_helper"

module SoulLink
  class GameStateAbilitiesTest < ActiveSupport::TestCase
    test "all_abilities returns the sorted unique union" do
      abilities = SoulLink::GameState.all_abilities

      assert_equal 123, abilities.length
      assert_equal abilities.uniq, abilities, "must be deduplicated"
      assert_equal abilities.sort, abilities, "must be sorted"
      assert_includes abilities, "Overgrow"
      assert_includes abilities, "Blaze"
    end

    test "all_abilities is a superset of any single species' abilities" do
      SoulLink::GameState.abilities_for("Bulbasaur").each do |ability|
        assert_includes SoulLink::GameState.all_abilities, ability
      end
    end
  end
end
