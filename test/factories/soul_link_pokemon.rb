# Mirrors `test/fixtures/soul_link_pokemon.yml` — Step 4 of the FactoryBot
# conversion plan. The fixture is ERB-generated as a 6 routes x 4 players
# grid; this factory keeps the same shape via a data table + metaprogrammed
# trait loop so future maintainers see the same structure as the fixture.
#
# Trait names match the fixture keys: `:route201_grey` mirrors
# `pkmn_route201_grey`, etc. Traits intentionally do NOT set the
# `soul_link_pokemon_group` association — Step 5's test conversion will
# pass the matching group explicitly from each test's local `groups`
# variable.
FactoryBot.define do
  factory :soul_link_pokemon do
    association :soul_link_run
    association :soul_link_pokemon_group
    sequence(:discord_user_id) { |n| 153665622641737728 + n }
    sequence(:species) { |n| "Species#{n}" }
    name { species }
    sequence(:location) { |n| "route_#{200 + n}" }
    status { "caught" }

    SOUL_LINK_POKEMON_PLAYERS = [
      { suffix: :grey,      discord_user_id: 153665622641737728 },
      { suffix: :aratypuss, discord_user_id: 600802903967531093 },
      { suffix: :scythe461, discord_user_id: 189518174125817856 },
      { suffix: :zealous,   discord_user_id: 182742127061630976 }
    ].freeze

    SOUL_LINK_POKEMON_ROUTES = [
      { route_key: :route201, location: "route_201", species: %w[Starly Bidoof Shinx Kricketot] },
      { route_key: :route202, location: "route_202", species: %w[Budew Zubat Geodude Machop] },
      { route_key: :route203, location: "route_203", species: %w[Abra Ponyta Gastly Roselia] },
      { route_key: :route204, location: "route_204", species: %w[Buizel Shellos Pachirisu Aipom] },
      { route_key: :route205, location: "route_205", species: %w[Eevee Murkrow Misdreavus Gligar] },
      { route_key: :route206, location: "route_206", species: %w[Bronzor Chingling Meditite Stunky] }
    ].freeze

    SOUL_LINK_POKEMON_ROUTES.each do |route|
      SOUL_LINK_POKEMON_PLAYERS.each_with_index do |player, idx|
        trait_name = :"#{route[:route_key]}_#{player[:suffix]}"
        trait_species = route[:species][idx]
        trait_location = route[:location]
        trait_uid = player[:discord_user_id]

        trait trait_name do
          discord_user_id { trait_uid }
          species { trait_species }
          name { trait_species }
          location { trait_location }
          status { "caught" }
        end
      end
    end
  end
end
