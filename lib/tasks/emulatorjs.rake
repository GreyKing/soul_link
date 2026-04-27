require "net/http"
require "json"
require "fileutils"
require "tmpdir"
require "open3"
require "uri"

module EmulatorJSInstaller
  REPO = "EmulatorJS/EmulatorJS".freeze
  USER_AGENT = "soul_link-emulatorjs-installer".freeze
  MAX_REDIRECTS = 5

  module_function

  def fetch_release(version)
    path = version ? "/repos/#{REPO}/releases/tags/#{version}" : "/repos/#{REPO}/releases/latest"
    url = "https://api.github.com#{path}"
    body = http_get_body(url)
    JSON.parse(body)
  rescue JSON::ParserError => e
    raise "Failed to parse GitHub release JSON from #{url}: #{e.message}"
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

  def extract_tarball(tarball_path, into_dir)
    stdout, stderr, status = Open3.capture3("tar", "-xzf", tarball_path, "-C", into_dir)
    return if status.success?
    raise "tar failed extracting #{tarball_path} into #{into_dir} (exit #{status.exitstatus}): #{stderr.strip}\n#{stdout.strip}"
  end

  # Locate the single top-level `EmulatorJS-EmulatorJS-<sha>/` wrapper directory.
  def locate_wrapper_dir(extracted_root)
    entries = Dir.children(extracted_root).reject { |n| n.start_with?(".") }
    if entries.size != 1
      raise "Expected exactly one top-level entry in extracted tarball, got #{entries.size}: #{entries.inspect}"
    end
    wrapper = File.join(extracted_root, entries.first)
    raise "Top-level entry #{entries.first.inspect} is not a directory" unless File.directory?(wrapper)
    wrapper
  end

  def move_contents(src_dir, dest_dir)
    FileUtils.mkdir_p(dest_dir)
    Dir.children(src_dir).each do |name|
      FileUtils.mv(File.join(src_dir, name), File.join(dest_dir, name))
    end
  end
end

namespace :emulatorjs do
  desc "Install EmulatorJS into public/emulatorjs/ from the upstream GitHub release (VERSION=v4.x to pin)"
  task :install do
    version = ENV["VERSION"]
    dest = Rails.root.join("public", "emulatorjs").to_s

    puts version ? "Fetching EmulatorJS release tag #{version}..." : "Fetching latest EmulatorJS release..."
    release = EmulatorJSInstaller.fetch_release(version)
    tag_name = release["tag_name"]
    tarball_url = release["tarball_url"]
    raise "Release JSON missing tag_name" if tag_name.nil? || tag_name.empty?
    raise "Release JSON missing tarball_url" if tarball_url.nil? || tarball_url.empty?
    puts "  Resolved version: #{tag_name}"
    puts "  Tarball URL: #{tarball_url}"

    Dir.mktmpdir("emulatorjs-install-") do |tmpdir|
      tarball_path = File.join(tmpdir, "emulatorjs.tar.gz")
      extract_dir = File.join(tmpdir, "extract")
      FileUtils.mkdir_p(extract_dir)

      puts "Downloading tarball..."
      EmulatorJSInstaller.download_to_file(tarball_url, tarball_path)
      puts "  Downloaded #{File.size(tarball_path)} bytes to #{tarball_path}"

      puts "Extracting..."
      EmulatorJSInstaller.extract_tarball(tarball_path, extract_dir)
      wrapper = EmulatorJSInstaller.locate_wrapper_dir(extract_dir)
      puts "  Wrapper directory: #{File.basename(wrapper)}"

      puts "Replacing #{dest}..."
      FileUtils.rm_rf(dest)
      FileUtils.mkdir_p(dest)
      EmulatorJSInstaller.move_contents(wrapper, dest)
    end

    puts "\nInstalled EmulatorJS #{tag_name} to #{dest}"
    top_level = Dir.children(dest).sort
    puts "Top-level entries (#{top_level.size}):"
    top_level.each do |name|
      full = File.join(dest, name)
      marker = File.directory?(full) ? "/" : ""
      puts "  #{name}#{marker}"
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
