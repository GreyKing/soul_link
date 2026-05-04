require "test_helper"

module SoulLink
  # Step 19 — WipeCoordinator contract tests. Covers the 5 scenarios
  # from the brief: brand-new run no-wipe, one-player-zero-alive wipe,
  # all-players-alive no-wipe, idempotent re-run, and post-clear re-fire.
  # Discord notifier is stubbed end-to-end (no real HTTP).
  class WipeCoordinatorTest < ActiveSupport::TestCase
    PLAYERS = [
      153665622641737728,   # Grey
      600802903967531093,   # ARatypuss
      189518174125817856,   # Scythe461
      182742127061630976    # ZealousZarathuuuustra
    ].freeze

    setup do
      @run = create(:soul_link_run)
      @notify_calls = []
    end

    # Replace `notify_wipe` with a recorder so tests can assert call
    # count + payload without hitting Discord.
    def with_notifier_recorder(&block)
      recorder = ->(run, uid, route) { @notify_calls << { run_id: run.id, uid: uid, route: route } }
      SoulLink::DiscordNotifier.stub(:notify_wipe, recorder, &block)
    end

    # Convenience: create a Pokemon row for a player with the given status.
    def pokemon(uid, status:, location: "Route 201", died_at: nil)
      create(:soul_link_pokemon,
             soul_link_run: @run,
             soul_link_pokemon_group: nil,
             discord_user_id: uid,
             species: "Bidoof",
             name: "Bidoof",
             location: location,
             status: status,
             died_at: died_at)
    end

    # ── (a) brand-new run, all players have 0 catches → no wipe ────────

    test "brand-new run with no catches at all → no wipe fires" do
      with_notifier_recorder do
        SoulLink::WipeCoordinator.process(@run)
      end
      assert_nil @run.reload.wiped_at
      assert_equal [], @notify_calls
    end

    # ── (b) one player has 1 alive, all others have 0 alive → wipe fires
    #     The 0-alive player triggers, NOT the 1-alive one.

    test "wipe fires when one player has caught Pokemon but zero alive" do
      # Player 0 has 1 dead, 0 alive → wipe trigger.
      pokemon(PLAYERS[0], status: "dead", location: "Route 205", died_at: 1.minute.ago)
      # Other players have 1 alive each (or no catches yet).
      pokemon(PLAYERS[1], status: "caught")
      pokemon(PLAYERS[2], status: "caught")
      pokemon(PLAYERS[3], status: "caught")

      with_notifier_recorder do
        SoulLink::WipeCoordinator.process(@run)
      end

      assert @run.reload.wiped_at.present?
      assert_equal 1, @notify_calls.size
      assert_equal PLAYERS[0],   @notify_calls.first[:uid]
      assert_equal "Route 205",  @notify_calls.first[:route]
    end

    # ── (c) all 4 players alive → no wipe ──────────────────────────────

    test "no wipe when all 4 players have at least one alive Pokemon" do
      PLAYERS.each { |uid| pokemon(uid, status: "caught") }

      with_notifier_recorder do
        SoulLink::WipeCoordinator.process(@run)
      end

      assert_nil @run.reload.wiped_at
      assert_equal [], @notify_calls
    end

    # ── (d) wipe already set, all conditions met → idempotent no-op ────

    test "idempotent: when wiped_at is already set, no second update! and no second notification" do
      pokemon(PLAYERS[0], status: "dead", died_at: 1.minute.ago)
      original = 2.days.ago.beginning_of_minute
      @run.update!(wiped_at: original)

      with_notifier_recorder do
        SoulLink::WipeCoordinator.process(@run)
      end

      assert_equal original.to_i, @run.reload.wiped_at.to_i
      assert_equal [], @notify_calls
    end

    # ── (e) wipe cleared, then re-fired → wipe fires again ─────────────

    test "after clearing wiped_at, a subsequent process call re-fires the wipe" do
      pokemon(PLAYERS[0], status: "dead", location: "Route 207", died_at: 1.minute.ago)

      # First fire.
      with_notifier_recorder { SoulLink::WipeCoordinator.process(@run) }
      assert @run.reload.wiped_at.present?
      assert_equal 1, @notify_calls.size

      # Clear wipe and re-process.
      @run.update!(wiped_at: nil)
      @notify_calls = []
      with_notifier_recorder { SoulLink::WipeCoordinator.process(@run) }

      assert @run.reload.wiped_at.present?
      assert_equal 1, @notify_calls.size
      assert_equal PLAYERS[0], @notify_calls.first[:uid]
    end

    # ── nil-run defense in depth ────────────────────────────────────────

    test "process(nil) is a silent no-op" do
      assert_nothing_raised do
        with_notifier_recorder { SoulLink::WipeCoordinator.process(nil) }
      end
      assert_equal [], @notify_calls
    end

    # ── empty-route fallback ────────────────────────────────────────────
    #
    # `location` is NOT NULL at the DB layer + `presence: true` at the AR
    # layer, so the dead Pokemon's row always has a location string in
    # production. The `|| "Unknown"` fallback in the coordinator is
    # belt-and-suspenders defense for an unknown future shape (e.g. a
    # raw SQL fixup that left the column blank). Not directly testable
    # without bypassing the validation layer; the safe-net branch is
    # left as defensive code.

    # ── picks the most recent death's location ──────────────────────────

    test "wipe route is the location of the most recently died Pokemon" do
      pokemon(PLAYERS[0], status: "dead", location: "Route 201", died_at: 3.minutes.ago)
      pokemon(PLAYERS[0], status: "dead", location: "Route 203", died_at: 1.minute.ago)
      pokemon(PLAYERS[0], status: "dead", location: "Route 202", died_at: 2.minutes.ago)

      with_notifier_recorder do
        SoulLink::WipeCoordinator.process(@run)
      end

      assert_equal "Route 203", @notify_calls.first[:route]
    end
  end
end
