module SoulLink
  # Resolves free-text species input (from a Discord modal) to a canonical
  # species name from `pokedex.yml`.
  #
  # Three tiers, in order:
  #   1. Exact match (case-insensitive)
  #   2. Unique prefix match
  #   3. Reject — ambiguous (with candidates) or unknown (without)
  #
  # Never guesses. An ambiguous input returns candidates so the caller can
  # tell the player what they might have meant.
  class SpeciesResolver
    MAX_CANDIDATES = 5

    Result = Struct.new(:species, :candidates, keyword_init: true) do
      def resolved? = species.present?
    end

    def self.call(input) = new(input).call

    def initialize(input)
      @input = input.to_s.strip
    end

    def call
      return reject([]) if @input.blank?

      exact = all_species.find { |s| s.casecmp?(@input) }
      return Result.new(species: exact, candidates: []) if exact

      prefixed = all_species.select { |s| s.downcase.start_with?(@input.downcase) }
      return Result.new(species: prefixed.first, candidates: []) if prefixed.one?

      reject(prefixed.first(MAX_CANDIDATES))
    end

    private

    def reject(candidates) = Result.new(species: nil, candidates: candidates)

    # `GameState.pokedex` is a `species name => sprite id` Hash — its keys are
    # the canonical species list. Same idiom as dashboard_controller.rb:104.
    def all_species = SoulLink::GameState.pokedex.keys
  end
end
