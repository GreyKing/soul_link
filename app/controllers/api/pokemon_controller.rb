module Api
  class PokemonController < BaseController
    def show
      species = params[:species]
      base_stat = Pokemon::BaseStat.find_by!(species: species)
      moves = base_stat.moves
        .where(category: %w[physical special])
        .distinct
        .order(:name)
        .select(:id, :name, :power, :move_type, :category)

      sprite_filename = SoulLink::GameState.sprite_filename(species)
      sprite_url = sprite_filename ? helpers.asset_path("sprites/#{sprite_filename}.png") : nil

      render json: {
        species: base_stat.species,
        sprite_url: sprite_url,
        types: [base_stat.type1, base_stat.type2].compact,
        stats: {
          hp: base_stat.hp, atk: base_stat.atk, def: base_stat.def_stat,
          spa: base_stat.spa, spd: base_stat.spd, spe: base_stat.spe
        },
        moves: moves.map { |m| { name: m.name, power: m.power, type: m.move_type, category: m.category } }
      }
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Pokemon not found" }, status: :not_found
    end
  end
end
