module ApplicationHelper
  # Renders a Pokemon sprite <img> tag for the given species name.
  # Returns empty string if species has no sprite mapping (graceful fallback).
  def pokemon_sprite_tag(species_name, size: 32)
    filename = SoulLink::GameState.sprite_filename(species_name)
    return "".html_safe unless filename

    image_tag("sprites/#{filename}.png",
      alt: species_name,
      width: size,
      height: size,
      class: "inline-block",
      loading: "lazy"
    )
  end
end
