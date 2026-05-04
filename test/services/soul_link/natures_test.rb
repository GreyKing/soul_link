require "test_helper"

module SoulLink
  class NaturesTest < ActiveSupport::TestCase
    test "all 25 canonical nature names are present in PKHeX/pret order" do
      assert_equal 25, SoulLink::Natures::NAMES.size
      # Spot-check anchor entries — first/last and a couple of mid-list
      # values that lock the order against the citation.
      assert_equal "Hardy",   SoulLink::Natures::NAMES[0]
      assert_equal "Lonely",  SoulLink::Natures::NAMES[1]
      assert_equal "Adamant", SoulLink::Natures::NAMES[3]
      assert_equal "Bold",    SoulLink::Natures::NAMES[5]
      assert_equal "Timid",   SoulLink::Natures::NAMES[10]
      assert_equal "Modest",  SoulLink::Natures::NAMES[15]
      assert_equal "Calm",    SoulLink::Natures::NAMES[20]
      assert_equal "Quirky",  SoulLink::Natures::NAMES[24]
    end

    test "name(0) returns Hardy and name(24) returns Quirky" do
      assert_equal "Hardy",  SoulLink::Natures.name(0)
      assert_equal "Quirky", SoulLink::Natures.name(24)
    end

    test "name returns the fallback for out-of-range input" do
      assert_equal "Nature #-1", SoulLink::Natures.name(-1)
      assert_equal "Nature #25", SoulLink::Natures.name(25)
      assert_equal "Nature #99", SoulLink::Natures.name(99)
    end

    test "name does not raise on nil or non-Integer input" do
      assert_nothing_raised do
        # nil and weird types fall into the fallback branch — nil.to_i is 0
        # but we still want a defensive path so we don't blow up the
        # coordinator.
        assert_kind_of String, SoulLink::Natures.name(nil)
        assert_kind_of String, SoulLink::Natures.name("oops")
        assert_kind_of String, SoulLink::Natures.name(3.5)
      end
    end

    test "NAMES array is frozen (cannot be mutated)" do
      assert SoulLink::Natures::NAMES.frozen?
    end

    test "matches the pid % 25 derivation for canonical PIDs" do
      # PID 0 → 0 (Hardy)
      assert_equal "Hardy", SoulLink::Natures.name(0 % 25)
      # PID 0xFFFFFFFF (4294967295) % 25 = 20 → Calm
      assert_equal "Calm",  SoulLink::Natures.name(0xFFFFFFFF % 25)
      # PID 12345 % 25 = 20 → Calm; sanity-check a non-trivial value
      assert_equal "Calm",  SoulLink::Natures.name(12345 % 25)
      # PID 100 % 25 = 0 → Hardy
      assert_equal "Hardy", SoulLink::Natures.name(100 % 25)
    end
  end
end
