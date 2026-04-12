module Api
  class CalculatorController < BaseController
    def calculate
      unless params[:attacker_species].present? && params[:defender_species].present? && params[:move_name].present?
        return render json: { error: "Missing required parameters" }, status: :unprocessable_entity
      end

      result = Pokemon::DamageCalculator.calculate(
        attacker: {
          species: params[:attacker_species],
          level: params[:attacker_level].to_i,
          nature: params[:attacker_nature].presence,
          evs: {}
        },
        defender: {
          species: params[:defender_species],
          level: params[:defender_level].to_i,
          nature: params[:defender_nature].presence,
          evs: {}
        },
        move: { name: params[:move_name] }
      )

      render json: result
    rescue ActiveRecord::RecordNotFound => e
      render json: { error: e.message }, status: :not_found
    end
  end
end
