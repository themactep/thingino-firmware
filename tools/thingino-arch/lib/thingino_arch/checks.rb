require "digest"
require "json"
require "set"

module ThinginoArch
  Finding = Struct.new(:id, :severity, :message, :path, :entity, :details, keyword_init: true) do
    def fingerprint
      Digest::SHA256.hexdigest([id, path, entity, message].join("\0"))
    end

    def to_h
      {
        "id" => id,
        "severity" => severity.to_s,
        "message" => message,
        "path" => path,
        "entity" => entity,
        "details" => details
      }
    end
  end

  class Baseline
    VERSION = 1

    def self.load(path)
      return Set.new unless File.file?(path)

      data = JSON.parse(File.read(path))
      Set.new(Array(data["findings"]))
    rescue JSON::ParserError
      Set.new
    end

    def self.write(path, findings)
      data = {
        "version" => VERSION,
        "generated_at" => Time.now.utc.iso8601,
        "findings" => findings.map(&:fingerprint).sort
      }
      File.write(path, JSON.pretty_generate(data) + "\n")
    end
  end

  class Checks
    SEVERITY_ORDER = { "error" => 0, "warning" => 1, "info" => 2 }.freeze
    WIFI_PREFIXES = %w[BR2_THINGINO_ BR2_PACKAGE_THINGINO_ BR2_PACKAGE_WIFI_ BR2_INGENIC_ BR2_SIGMASTAR_ BR2_SENSOR_].freeze
    STREAMER_FLAGS = %w[prudynt raptor timps strero].freeze

    attr_reader :index

    def initialize(index)
      @index = index
    end

    def run
      findings = []
      findings.concat(package_findings)
      findings.concat(camera_findings)
      findings.concat(wifi_findings)
      findings.concat(plugin_findings)
      findings.concat(init_findings)
      findings.concat(config_findings)
      findings.concat(soc_findings)
      findings.sort_by { |finding| [SEVERITY_ORDER[finding.severity], finding.path.to_s, finding.id, finding.message] }
    end

    private

    def package_findings
      findings = []
      reachable = index.reachable_config_files
      index.packages.each_value do |package|
        package["config_files"].each do |config_file|
          next if reachable.include?(config_file)

          severity = index.cameras_by_package[package["name"]].empty? ? "info" : "error"
          findings << finding(
            "package.unreachable_config",
            severity,
            "package #{package['name']} has a Config.in that is not reachable from the top-level Kconfig entry points",
            config_file,
            package["name"],
            "config_files" => package["config_files"]
          )
        end

        if package["remote"] && !package["has_hash"]
          findings << finding(
            "package.missing_hash",
            "warning",
            "remote package #{package['name']} has no hash file",
            package["mk_files"].first || package["dir"],
            package["name"],
            "site" => package["site"],
            "version" => package["version"]
          )
        end
      end
      findings
    end

    def camera_findings
      findings = []
      index.cameras.each_value do |camera|
        unless camera["name_matches_dir"]
          findings << finding(
            "camera.defconfig_name_mismatch",
            "error",
            "defconfig name #{camera['defconfig_name']} does not match profile directory #{camera['name']}",
            camera["defconfig"],
            camera["id"]
          )
        end

        if camera["soc_model"].to_s.empty?
          findings << finding(
            "camera.missing_soc",
            "error",
            "camera profile does not declare a SoC model",
            camera["defconfig"],
            camera["id"]
          )
        elsif !index.soc_models.key?(camera["soc_model"])
          findings << finding(
            "camera.unknown_soc",
            "error",
            "camera profile references unknown SoC model #{camera['soc_model']}",
            camera["defconfig"],
            camera["id"],
            "soc_model" => camera["soc_model"]
          )
        end

        if !camera["has_json"] && %w[cameras cameras-exp].include?(camera["group"])
          findings << finding(
            "camera.missing_json",
            "warning",
            "camera profile #{camera['id']} has no thingino.json",
            camera["defconfig"],
            camera["id"]
          )
        end

        if camera["wifi_symbols"].size > 1
          findings << finding(
            "camera.multiple_wifi",
            "error",
            "camera profile selects more than one Wi-Fi driver: #{camera['wifi_symbols'].join(', ')}",
            camera["defconfig"],
            camera["id"],
            "wifi_symbols" => camera["wifi_symbols"]
          )
        end

        camera["wifi_symbols"].each do |symbol|
          unless index.config_symbols.key?(symbol)
            findings << finding(
              "camera.unknown_wifi_symbol",
              "error",
              "camera profile selects undefined Wi-Fi symbol #{symbol}",
              camera["defconfig"],
              camera["id"],
              "symbol" => symbol
            )
          end

          next if index.wifi_drivers.key?(symbol)

          findings << finding(
            "camera.unregistered_wifi_driver",
            "error",
            "camera profile selects #{symbol}, which is not registered in package/wifi/wifi.mk",
            camera["defconfig"],
            camera["id"],
            "symbol" => symbol
          )
        end
      end
      findings
    end

    def wifi_findings
      findings = []
      index.wifi_drivers.each_value do |driver|
        symbol = driver["symbol"]
        unless index.config_symbols.key?(symbol)
          findings << finding(
            "wifi.undefined_symbol",
            "error",
            "WIFI_ADD_DRIVER registers undefined Kconfig symbol #{symbol}",
            "package/wifi/wifi.mk",
            symbol
          )
        end

        if driver["package"].nil?
          findings << finding(
            "wifi.missing_package",
            "warning",
            "Wi-Fi driver #{symbol} does not map to a package directory",
            "package/wifi/wifi.mk",
            symbol
          )
          next
        end

        if driver["module_name"].to_s.empty?
          findings << finding(
            "wifi.missing_module_name",
            "warning",
            "Wi-Fi driver #{symbol} has no module name in #{driver['package']}",
            package_config_path(driver["package"]),
            driver["package"],
            "symbol" => symbol
          )
        end

        if driver["interface"].to_s.empty? || driver["interface"].include?("$(")
          findings << finding(
            "wifi.unresolved_interface",
            "info",
            "Wi-Fi driver #{symbol} has a dynamic or empty interface value: #{driver['interface']}",
            "package/wifi/wifi.mk",
            symbol
          )
        end
      end
      findings
    end

    def plugin_findings
      findings = []
      names = {}
      pages = {}
      cgis = {}

      index.plugins.each do |plugin|
        if plugin["error"]
          findings << finding(
            "plugin.invalid_json",
            "error",
            "webui plugin manifest is invalid: #{plugin['error']}",
            plugin["path"],
            plugin["package"]
          )
          next
        end

        name = plugin["name"]
        if name.nil? || name.empty?
          findings << finding(
            "plugin.missing_name",
            "error",
            "webui plugin manifest has no name",
            plugin["path"],
            plugin["package"]
          )
        elsif names.key?(name)
          other = names[name]
          coexistence = packages_coexist?(plugin["package"], other["package"])
          findings << finding(
            "plugin.duplicate_name",
            coexistence ? "error" : "info",
            "webui plugin name #{name} is already declared by #{other['path']}",
            plugin["path"],
            name,
            "other" => other["path"],
            "coexist" => coexistence
          )
        else
          names[name] = plugin
        end

        plugin["pages"].each do |page|
          other = pages[page]
          if other && !exclusive_plugins?(plugin, other)
            coexistence = packages_coexist?(plugin["package"], other["package"])
            findings << finding(
              "plugin.duplicate_page",
              coexistence ? "error" : "info",
              "webui page #{page} is already claimed by plugin #{other['name']}",
              plugin["path"],
              name,
              "page" => page,
              "other" => other["path"],
              "coexist" => coexistence
            )
          else
            pages[page] ||= plugin
          end
        end

        plugin["cgi"].each do |cgi|
          other = cgis[cgi]
          if other && !exclusive_plugins?(plugin, other)
            coexistence = packages_coexist?(plugin["package"], other["package"])
            findings << finding(
              "plugin.duplicate_cgi",
              coexistence ? "warning" : "info",
              "CGI endpoint #{cgi} is also claimed by plugin #{other['name']}",
              plugin["path"],
              name,
              "cgi" => cgi,
              "other" => other["path"],
              "coexist" => coexistence
            )
          else
            cgis[cgi] ||= plugin
          end
        end
      end
      findings
    end

    def init_findings
      findings = []
      index.init_by_basename.each do |basename, entries|
        next if entries.size < 2

        packages = entries.map { |entry| entry["package"] }.compact.uniq
        coexistence = packages.combination(2).any? { |left, right| packages_coexist?(left, right) }
        severity = coexistence ? "warning" : "info"
        findings << finding(
          "init.duplicate_basename",
          severity,
          "init script #{basename} is installed by multiple packages: #{packages.join(', ')}",
          entries.first["path"],
          basename,
          "paths" => entries.map { |entry| entry["path"] },
          "coexist" => coexistence
        )
      end
      findings
    end

    def config_findings
      findings = []
      seen = Set.new
      index.cameras.each_value do |camera|
        camera["own_symbols"].each do |symbol, _value|
          next unless WIFI_PREFIXES.any? { |prefix| symbol.start_with?(prefix) }
          next if index.config_symbols.key?(symbol)
          next unless seen.add?([camera["defconfig"], symbol])

          findings << finding(
            "config.unknown_symbol",
            "warning",
            "camera profile references undefined Thingino symbol #{symbol}",
            camera["defconfig"],
            camera["id"],
            "symbol" => symbol
          )
        end
      end

      index.fragments.each_value do |fragment|
        fragment["symbols"].each_key do |symbol|
          next unless WIFI_PREFIXES.any? { |prefix| symbol.start_with?(prefix) }
          next if index.config_symbols.key?(symbol)
          next unless seen.add?([fragment["path"], symbol])

          findings << finding(
            "config.unknown_symbol",
            "warning",
            "fragment references undefined Thingino symbol #{symbol}",
            fragment["path"],
            fragment["name"],
            "symbol" => symbol
          )
        end
      end
      findings
    end

    def soc_findings
      index.soc_model_conflicts.map do |conflict|
        finding(
          "soc.model_conflict",
          "error",
          "SoC model #{conflict['model']} is claimed by multiple families",
          conflict.dig("second", "file"),
          conflict["model"],
          "first" => conflict["first"],
          "second" => conflict["second"]
        )
      end
    end

    def finding(id, severity, message, path, entity, details = {})
      Finding.new(id: id, severity: severity, message: message, path: path, entity: entity, details: details)
    end

    def package_config_path(package_name)
      package = index.packages[package_name]
      package&.dig("config_files", 0) || package&.dig("mk_files", 0) || "package/#{package_name}"
    end

    def exclusive_plugins?(left, right)
      left_flag = streamer_flag(left)
      right_flag = streamer_flag(right)
      !left_flag.nil? && !right_flag.nil? && left_flag != right_flag
    end

    def streamer_flag(plugin)
      plugin["feature_flags"].keys.find { |key| STREAMER_FLAGS.include?(key) }
    end

    def packages_coexist?(left, right)
      return false if left.nil? || right.nil?

      left_cameras = index.cameras_by_package[left]
      right_cameras = index.cameras_by_package[right]
      (left_cameras & right_cameras).any?
    end
  end
end
