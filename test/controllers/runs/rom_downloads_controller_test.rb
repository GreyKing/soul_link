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
