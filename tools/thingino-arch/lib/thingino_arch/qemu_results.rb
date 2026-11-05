require "fileutils"
require "json"
require "open3"
require "tmpdir"

module ThinginoArch
  class QemuResults
    attr_reader :repo, :run_id, :repo_slug, :profiles, :results, :run_url

    def initialize(repo:, run_id:, repo_slug:, profiles:)
      @repo = repo
      @run_id = run_id.to_s
      @repo_slug = repo_slug
      @profiles = profiles
      @results = []
      @run_url = nil
      fetch
    end

    def to_h
      {
        "run_id" => run_id,
        "run_url" => run_url,
        "repo" => repo_slug,
        "profiles" => results
      }
    end

    def text
      lines = ["QEMU results for run #{run_id}"]
      lines << "Run: #{run_url}" if run_url
      results.each do |result|
        if result["error"]
          lines << "#{result['profile']}: ERROR #{result['error']}"
          next
        end
        summary = "#{result['profile']}: #{result['passed']}/#{result['checks']} checks passed"
        if result["playwright"]
          stats = result["playwright"]
          summary += "; Playwright expected #{stats['expected']}, unexpected #{stats['unexpected']}, flaky #{stats['flaky']}"
        end
        lines << summary
        result["failures"].each do |failure|
          lines << "  FAIL #{failure['name']}: #{failure['detail']}"
        end
      end
      lines.join("\n")
    end

    def self.parse_profile(directory, profile)
      result = {
        "profile" => profile,
        "checks" => 0,
        "passed" => 0,
        "failed" => 0,
        "failures" => [],
        "playwright" => nil,
        "error" => nil
      }
      serial_path = Dir.glob(File.join(directory, "**", "serial-results.json")).first
      playwright_path = Dir.glob(File.join(directory, "**", "playwright-results.json")).first

      if serial_path
        checks = JSON.parse(File.read(serial_path))
        result["checks"] = checks.size
        result["passed"] = checks.count { |check| check["pass"] }
        result["failed"] = result["checks"] - result["passed"]
        result["failures"] = checks.reject { |check| check["pass"] }.map do |check|
          { "name" => check["name"], "detail" => check["detail"] }
        end
      else
        result["error"] = "serial-results.json not found"
      end

      if playwright_path
        playwright = JSON.parse(File.read(playwright_path))
        result["playwright"] = playwright["stats"] || {}
      end
      result
    rescue JSON::ParserError => error
      result["error"] = "invalid JSON: #{error.message}"
      result
    end

    private

    def fetch
      unless repo_slug
        results << { "profile" => profiles.join(", "), "error" => "GitHub repository not configured" }
        return
      end

      @run_url = fetch_run_url
      profiles.each do |profile|
        directory = Dir.mktmpdir("thingino-qemu-#{profile}")
        begin
          _stdout, stderr, status = Open3.capture3(
            "gh", "run", "download", run_id,
            "-R", repo_slug,
            "-n", "qemu-test-report-#{profile}",
            "-D", directory
          )
          unless status.success?
            results << { "profile" => profile, "error" => stderr.strip }
            next
          end
          results << self.class.parse_profile(directory, profile)
        ensure
          FileUtils.remove_entry(directory) if File.directory?(directory)
        end
      end
    rescue Errno::ENOENT
      results << { "profile" => profiles.join(", "), "error" => "gh is not installed" }
    end

    def fetch_run_url
      stdout, _stderr, status = Open3.capture3(
        "gh", "run", "view", run_id,
        "-R", repo_slug,
        "--json", "url",
        "--jq", ".url"
      )
      status.success? ? stdout.strip : nil
    rescue Errno::ENOENT
      nil
    end
  end
end
