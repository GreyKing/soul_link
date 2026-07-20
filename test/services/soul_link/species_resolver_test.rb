require "test_helper"

module SoulLink
  class SpeciesResolverTest < ActiveSupport::TestCase
    test "exact match is case-insensitive" do
      result = SoulLink::SpeciesResolver.call("staravia")
      assert result.resolved?
      assert_equal "Staravia", result.species
    end

    test "unique prefix resolves" do
      result = SoulLink::SpeciesResolver.call("staravi")
      assert result.resolved?
      assert_equal "Staravia", result.species
    end

    test "ambiguous prefix is rejected with candidates" do
      result = SoulLink::SpeciesResolver.call("star")
      refute result.resolved?
      assert_includes result.candidates, "Staravia"
      assert_includes result.candidates, "Starly"
      assert_operator result.candidates.length, :<=, 5
    end

    test "unknown input is rejected with no candidates" do
      result = SoulLink::SpeciesResolver.call("zzzzznotapokemon")
      refute result.resolved?
      assert_empty result.candidates
    end

    test "blank input is rejected" do
      refute SoulLink::SpeciesResolver.call("").resolved?
      refute SoulLink::SpeciesResolver.call(nil).resolved?
    end

    test "an exact name that is a strict prefix of another species still resolves" do
      # "Mew" is a strict prefix of "Mewtwo" — without the exact-match tier
      # winning, this would fall through to an ambiguous prefix rejection.
      result = SoulLink::SpeciesResolver.call("Mew")
      assert result.resolved?
      assert_equal "Mew", result.species
    end

    test "candidate list is capped at MAX_CANDIDATES" do
      result = SoulLink::SpeciesResolver.call("s")
      refute result.resolved?
      assert_equal SoulLink::SpeciesResolver::MAX_CANDIDATES, result.candidates.length
    end
  end
end
