require "test_helper"

module SoulLink
  class GenerateRomDownloadJobTest < ActiveSupport::TestCase
    setup do
      @run = create(:soul_link_run)
      @download = create(:soul_link_rom_download, soul_link_run: @run)
    end

    test "marks the download ready on success" do
      SoulLink::RomRandomizer.stub(:generate_to, ->(_path) { [ true, nil ] }) do
        SoulLink::GenerateRomDownloadJob.perform_now(@download.id)
      end

      @download.reload
      assert_equal "ready", @download.status
      assert @download.rom_path.present?
      assert_nil @download.error_message
    end

    test "marks the download failed with the reason" do
      SoulLink::RomRandomizer.stub(:generate_to, ->(_path) { [ false, "Java is not installed" ] }) do
        SoulLink::GenerateRomDownloadJob.perform_now(@download.id)
      end

      @download.reload
      assert_equal "failed", @download.status
      assert_equal "Java is not installed", @download.error_message
    end

    test "is a no-op for a missing download id" do
      assert_nothing_raised { SoulLink::GenerateRomDownloadJob.perform_now(0) }
    end

    test "truncates an overlong error to the column limit" do
      SoulLink::RomRandomizer.stub(:generate_to, ->(_path) { [ false, "x" * 500 ] }) do
        SoulLink::GenerateRomDownloadJob.perform_now(@download.id)
      end

      assert_operator @download.reload.error_message.length, :<=, 255
    end
  end
end
