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

  # Renders colored type badge pills for a species (1-2 badges).
  # Returns empty string if no types known.
  def pokemon_type_badges(species_name, size: :sm)
    types = SoulLink::GameState.types_for(species_name)
    return "".html_safe if types.empty?

    safe_join(types.map { |t| pokemon_type_badge(t, size: size) }, " ")
  end

  # Renders a single type badge pill.
  def pokemon_type_badge(type_name, size: :sm)
    colors = pokemon_type_colors(type_name)
    text_class = size == :xs ? "text-[10px] px-1.5 py-0" : "text-xs px-2 py-0.5"
    content_tag(:span, type_name,
      class: "inline-block rounded-full font-medium #{text_class} #{colors}")
  end

  private

  # Tailwind color classes for each Pokemon type.
  def pokemon_type_colors(type_name)
    {
      "Normal"   => "bg-gray-500/30 text-gray-300",
      "Fire"     => "bg-red-600/30 text-red-300",
      "Water"    => "bg-blue-600/30 text-blue-300",
      "Electric" => "bg-yellow-500/30 text-yellow-300",
      "Grass"    => "bg-green-600/30 text-green-300",
      "Ice"      => "bg-cyan-400/30 text-cyan-300",
      "Fighting" => "bg-orange-700/30 text-orange-300",
      "Poison"   => "bg-purple-600/30 text-purple-300",
      "Ground"   => "bg-amber-700/30 text-amber-300",
      "Flying"   => "bg-indigo-400/30 text-indigo-300",
      "Psychic"  => "bg-pink-500/30 text-pink-300",
      "Bug"      => "bg-lime-600/30 text-lime-300",
      "Rock"     => "bg-stone-600/30 text-stone-300",
      "Ghost"    => "bg-violet-700/30 text-violet-300",
      "Dragon"   => "bg-indigo-700/30 text-indigo-200",
      "Dark"     => "bg-gray-700/30 text-gray-200",
      "Steel"    => "bg-slate-500/30 text-slate-300"
    }.fetch(type_name, "bg-gray-600/30 text-gray-400")
  end
end
