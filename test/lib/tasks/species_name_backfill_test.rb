require "test_helper"
require "rake"

class SpeciesNameBackfillTaskTest < ActiveSupport::TestCase
  TASK_NAME = "soul_link:backfill_species_names".freeze

  @loaded = false
  class << self
    attr_accessor :loaded
  end

  setup do
    unless self.class.loaded
      Rails.application.load_tasks
      self.class.loaded = true
    end
    Rake::Task[TASK_NAME].reenable

    Pokemon::BaseStat.create!(species: "Turtwig", national_dex_number: 387, type1: "grass",
                              hp: 55, atk: 68, def_stat: 64, spa: 45, spd: 55, spe: 31)
    @run = create(:soul_link_run)
  end

  def catch_row(species, name: species)
    create(:soul_link_pokemon, soul_link_run: @run, soul_link_pokemon_group: nil,
           species: species, name: name)
  end

  def invoke
    capture_io { Rake::Task[TASK_NAME].invoke }
  end

  test "replaces placeholder species and a matching placeholder name" do
    row = catch_row("Species #387")

    invoke

    row.reload
    assert_equal "Turtwig", row.species
    assert_equal "Turtwig", row.name
  end

  test "keeps a name the player changed" do
    row = catch_row("Species #387", name: "SHELLY")

    invoke

    assert_equal "Turtwig", row.reload.species
    assert_equal "SHELLY", row.name
  end

  test "leaves real names and unknown dex numbers alone" do
    real = catch_row("Bidoof")
    unknown = catch_row("Species #999")

    invoke

    assert_equal "Bidoof", real.reload.species
    assert_equal "Species #999", unknown.reload.species
  end

  test "DRY_RUN makes no changes" do
    row = catch_row("Species #387")

    ENV["DRY_RUN"] = "1"
    invoke
    ENV.delete("DRY_RUN")

    assert_equal "Species #387", row.reload.species
  end
end
