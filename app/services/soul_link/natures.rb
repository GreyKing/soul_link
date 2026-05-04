module SoulLink
  # Gen-IV nature lookup. Nature is derived from `pid % 25`; this module
  # maps the numeric nature ID (0..24) to its canonical English name.
  #
  # **Pure constant module — zero AR, zero clock, never raises.**
  # `name(id)` returns a `"Nature ##{id}"` fallback for out-of-range
  # input rather than raising; the decoder layer should always pass a
  # well-formed Integer (`pid % 25`), but the defensive fallback matches
  # the rest of the SRAM-tracking stack.
  #
  # Source: PKHeX `PKHeX.Core/PKM/Nature.cs` defines the 25-entry enum
  # (Hardy=0..Quirky=24) in this exact order; pret/pokeplatinum
  # `include/constants/pokemon.h` matches via `enum Nature` and
  # `Pokemon_GetNature(personality % 25)`. Cross-referenced against
  # Bulbapedia's "Nature" article — same canonical order.
  module Natures
    NAMES = %w[
      Hardy Lonely Brave Adamant Naughty
      Bold Docile Relaxed Impish Lax
      Timid Hasty Serious Jolly Naive
      Modest Mild Quiet Bashful Rash
      Calm Gentle Sassy Careful Quirky
    ].freeze

    # @param id [Integer, nil] nature index 0..24 (typically `pid % 25`)
    # @return [String] canonical name, or `"Nature ##{id}"` fallback
    def self.name(id)
      idx = id.to_i
      return NAMES[idx] if idx.between?(0, NAMES.size - 1) && id.is_a?(Integer)
      "Nature ##{id}"
    end
  end
end
