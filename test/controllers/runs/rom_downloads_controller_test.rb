require "test_helper"

module Runs
  class RomDownloadsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @run = create(:soul_link_run)
      @user_id = SoulLink::GameState.players.first["discord_user_id"]
      login_as(@user_id)
    end

    test "create queues a job and returns the download id" do
      assert_enqueued_with(job: SoulLink::GenerateRomDownloadJob) do
        post run_rom_downloads_path(@run), as: :json
      end

      assert_response :success
      assert JSON.parse(response.body)["id"].present?
    end

    # Generation spawns a 30s Java subprocess, so `create` is idempotent while
    # work is in flight: a repeat POST reattaches to the existing download
    # rather than queueing a second subprocess.
    test "create reuses a pending download and enqueues no second job" do
      existing = create(:soul_link_rom_download, soul_link_run: @run,
                        discord_user_id: @user_id, status: "pending")

      assert_no_enqueued_jobs do
        post run_rom_downloads_path(@run), as: :json
      end

      assert_response :success
      body = JSON.parse(response.body)
      assert_equal existing.id, body["id"]
      assert_equal "pending", body["status"]
      assert_equal 1, @run.soul_link_rom_downloads.count
    end

    test "create reuses a generating download and enqueues no second job" do
      existing = create(:soul_link_rom_download, soul_link_run: @run,
                        discord_user_id: @user_id, status: "generating")

      assert_no_enqueued_jobs do
        post run_rom_downloads_path(@run), as: :json
      end

      assert_response :success
      assert_equal existing.id, JSON.parse(response.body)["id"]
      assert_equal 1, @run.soul_link_rom_downloads.count
    end

    # The guard must release once work finishes — a player is allowed to come
    # back for a fresh ROM. A guard that ignored `status` would trap them.
    test "create makes a new download once the previous one is ready" do
      finished = create(:soul_link_rom_download, soul_link_run: @run,
                        discord_user_id: @user_id, status: "ready",
                        rom_path: "storage/roms/downloads/done.nds")

      assert_enqueued_with(job: SoulLink::GenerateRomDownloadJob) do
        post run_rom_downloads_path(@run), as: :json
      end

      assert_response :success
      assert_not_equal finished.id, JSON.parse(response.body)["id"]
      assert_equal 2, @run.soul_link_rom_downloads.count
    end

    # The in-flight guard is per player, not per run — one player generating
    # must not block the other three.
    test "create is not blocked by another player's in-flight download" do
      other_id = SoulLink::GameState.players.second["discord_user_id"]
      create(:soul_link_rom_download, soul_link_run: @run,
             discord_user_id: other_id, status: "generating")

      assert_enqueued_with(job: SoulLink::GenerateRomDownloadJob) do
        post run_rom_downloads_path(@run), as: :json
      end

      assert_response :success
      assert_equal 2, @run.soul_link_rom_downloads.count
      assert_equal 1, @run.soul_link_rom_downloads.where(discord_user_id: @user_id).count
    end

    test "show reports status for polling" do
      download = create(:soul_link_rom_download, soul_link_run: @run,
                        discord_user_id: @user_id, status: "generating")

      get run_rom_download_path(@run, download), as: :json

      assert_response :success
      assert_equal "generating", JSON.parse(response.body)["status"]
    end

    test "download 404s when the rom is not ready" do
      download = create(:soul_link_rom_download, soul_link_run: @run,
                        discord_user_id: @user_id, status: "generating")

      get download_run_rom_download_path(@run, download)
      assert_response :not_found
    end

    test "download 404s for a different user's rom" do
      download = create(:soul_link_rom_download, soul_link_run: @run,
                        discord_user_id: @user_id + 1, status: "ready",
                        rom_path: "storage/roms/downloads/nope.nds")

      get download_run_rom_download_path(@run, download)
      assert_response :not_found
    end

    test "download 404s when the file is gone from disk" do
      download = create(:soul_link_rom_download, soul_link_run: @run,
                        discord_user_id: @user_id, status: "ready",
                        rom_path: "storage/roms/downloads/pruned.nds")

      get download_run_rom_download_path(@run, download)
      assert_response :not_found
    end
  end
end
