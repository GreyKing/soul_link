require "net/http"
require "json"
require "fileutils"
require "tmpdir"
require "open3"
require "uri"

module EmulatorJSInstaller
  # EmulatorJS publishes built bundles as a `.7z` release asset on their
  # main repo (e.g. `4.2.3.7z`, ~300MB). The auto-generated source tarball
  # only contains the unbuilt source tree (data/src/...), which forces the
  # loader into its FAILSAFE path with known runtime bugs (setImmediates.shift).
  # Self-hosting requires the 7z asset; that requires `7z` (p7zip) on PATH.
  REPO = "EmulatorJS/EmulatorJS".freeze
  USER_AGENT = "soul_link-emulatorjs-installer".freeze
  MAX_REDIRECTS = 5

  # File whose presence we treat as proof of a complete install. Only present
  # when the built bundle was extracted (not in the source-only tarball).
  INSTALL_MARKER = "data/emulator.min.js".freeze

  module_function

  # Hits the GitHub API and returns [tag_name, asset_url] for the .7z bundle
  # of either a specific release tag or the latest release.
  def fetch_release_asset(version)
    path = version ? "/repos/#{REPO}/releases/tags/#{version}" : "/repos/#{REPO}/releases/latest"
    url  = "https://api.github.com#{path}"
    release = JSON.parse(http_get_body(url))
    tag_name = release["tag_name"]
    raise "Release JSON missing tag_name from #{url}" if tag_name.nil? || tag_name.empty?

    asset = (release["assets"] || []).find { |a| a["name"].to_s.end_with?(".7z") }
    raise "No .7z asset found in release #{tag_name}" unless asset
    [tag_name, asset["browser_download_url"]]
  rescue JSON::ParserError => e
    raise "Failed to parse GitHub release JSON from #{url}: #{e.message}"
  end

  def seven_zip_available?
    system("command -v 7z > /dev/null 2>&1")
  end

  def extract_7z(archive_path, into_dir)
    stdout, stderr, status = Open3.capture3("7z", "x", archive_path, "-o#{into_dir}", "-y")
    return if status.success?
    raise "7z failed extracting #{archive_path} into #{into_dir} (exit #{status.exitstatus}): #{stderr.strip}\n#{stdout.strip}"
  end

  # The 7z extracts to `<extract_dir>/data/...`. If the archive ever changes
  # to wrap in a version-named dir, locate_data_dir will recurse to find it.
  def locate_data_dir(extract_dir)
    direct = File.join(extract_dir, "data")
    return direct if File.directory?(direct)

    # Fallback: walk one level deeper for a wrapper dir (e.g. `4.2.3/data/`).
    Dir.children(extract_dir).each do |entry|
      candidate = File.join(extract_dir, entry, "data")
      return candidate if File.directory?(candidate)
    end
    raise "Could not locate `data/` directory in extracted archive at #{extract_dir}. Layout: #{Dir.glob("#{extract_dir}/**/*").first(20).inspect}"
  end

  # GET that follows up to MAX_REDIRECTS redirects manually. Returns the body string.
  def http_get_body(url, redirects_left = MAX_REDIRECTS)
    raise "Too many redirects fetching #{url}" if redirects_left.negative?

    uri = URI.parse(url)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      request = Net::HTTP::Get.new(uri.request_uri)
      request["User-Agent"] = USER_AGENT
      request["Accept"] = "application/vnd.github+json"
      response = http.request(request)

      case response
      when Net::HTTPSuccess
        return response.body
      when Net::HTTPRedirection
        location = response["location"]
        raise "Redirect with no Location header from #{url}" if location.nil? || location.empty?
        return http_get_body(URI.join(url, location).to_s, redirects_left - 1)
      else
        raise "HTTP #{response.code} fetching #{url}: #{response.body.to_s[0, 200]}"
      end
    end
  end

  def download_to_file(url, dest_path, redirects_left = MAX_REDIRECTS)
    raise "Too many redirects downloading #{url}" if redirects_left.negative?

    uri = URI.parse(url)
    Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
      request = Net::HTTP::Get.new(uri.request_uri)
      request["User-Agent"] = USER_AGENT
      http.request(request) do |response|
        case response
        when Net::HTTPSuccess
          File.open(dest_path, "wb") do |io|
            response.read_body { |chunk| io.write(chunk) }
          end
          return dest_path
        when Net::HTTPRedirection
          location = response["location"]
          raise "Redirect with no Location header from #{url}" if location.nil? || location.empty?
          return download_to_file(URI.join(url, location).to_s, dest_path, redirects_left - 1)
        else
          raise "HTTP #{response.code} downloading #{url}"
        end
      end
    end
  end

  def move_contents(src_dir, dest_dir)
    FileUtils.mkdir_p(dest_dir)
    Dir.children(src_dir).each do |name|
      FileUtils.mv(File.join(src_dir, name), File.join(dest_dir, name))
    end
  end
end

namespace :emulatorjs do
  desc "Install EmulatorJS into public/emulatorjs/ from the official .7z release asset (VERSION=vX.Y.Z to pin)"
  task :install do
    unless EmulatorJSInstaller.seven_zip_available?
      raise "7z (p7zip) is required to extract the EmulatorJS release. Install with `apt install -y p7zip-full` (Linux) or `brew install p7zip` (macOS)."
    end

    version = ENV["VERSION"]
    dest = Rails.root.join("public", "emulatorjs").to_s

    puts version ? "Fetching EmulatorJS release tag #{version}..." : "Fetching latest EmulatorJS release..."
    tag_name, asset_url = EmulatorJSInstaller.fetch_release_asset(version)
    puts "  Resolved version: #{tag_name}"
    puts "  Asset URL: #{asset_url}"

    Dir.mktmpdir("emulatorjs-install-") do |tmpdir|
      archive_path = File.join(tmpdir, "emulatorjs.7z")
      extract_dir = File.join(tmpdir, "extract")
      FileUtils.mkdir_p(extract_dir)

      puts "Downloading .7z asset (~300MB, may take a minute)..."
      EmulatorJSInstaller.download_to_file(asset_url, archive_path)
      puts "  Downloaded #{File.size(archive_path)} bytes"

      puts "Extracting..."
      EmulatorJSInstaller.extract_7z(archive_path, extract_dir)
      data_src = EmulatorJSInstaller.locate_data_dir(extract_dir)
      puts "  Source data dir: #{data_src}"

      puts "Replacing #{dest}..."
      FileUtils.rm_rf(dest)
      FileUtils.mkdir_p(File.join(dest, "data"))
      EmulatorJSInstaller.move_contents(data_src, File.join(dest, "data"))
    end

    puts "\nInstalled EmulatorJS #{tag_name} to #{dest}"
    top_level = Dir.children(File.join(dest, "data")).sort.first(20)
    puts "data/ entries (showing first 20):"
    top_level.each do |name|
      full = File.join(dest, "data", name)
      marker = File.directory?(full) ? "/" : ""
      puts "  data/#{name}#{marker}"
    end

    marker_path = File.join(dest, EmulatorJSInstaller::INSTALL_MARKER)
    if File.exist?(marker_path)
      puts "✓ Install marker present (#{EmulatorJSInstaller::INSTALL_MARKER})"
    else
      warn "⚠ Install marker missing (#{EmulatorJSInstaller::INSTALL_MARKER}) — release layout may have changed"
    end
  end

  desc "Install EmulatorJS only if the marker file is missing (idempotent for deploys)"
  task :ensure_installed do
    dest = Rails.root.join("public", "emulatorjs").to_s
    marker_path = File.join(dest, EmulatorJSInstaller::INSTALL_MARKER)

    if File.exist?(marker_path)
      puts "EmulatorJS already installed (#{EmulatorJSInstaller::INSTALL_MARKER} present); skipping."
    else
      puts "EmulatorJS marker missing; running install..."
      Rake::Task["emulatorjs:install"].invoke
    end
  end

  desc "Remove public/emulatorjs/"
  task :clean do
    dest = Rails.root.join("public", "emulatorjs")
    if File.exist?(dest)
      FileUtils.rm_rf(dest)
      puts "Removed public/emulatorjs/"
    else
      puts "public/emulatorjs/ already absent"
    end
  end
end
