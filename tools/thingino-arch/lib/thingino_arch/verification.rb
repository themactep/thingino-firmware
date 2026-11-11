require "set"
require "shellwords"

module ThinginoArch
  class Verification
    DEFAULT_FAMILIES = %w[t31 t41].freeze
    DEFAULT_MAX_PROFILES = 4
    NET_SCORE = { "tap" => 3, "slirp" => 2, "slip" => 1 }.freeze
    BROAD_CHANGE_RATIO = 0.5

    attr_reader :index, :impact, :profiles, :suites, :flags, :skipped, :notes, :families

    def initialize(index, impact, max_profiles: DEFAULT_MAX_PROFILES, only: nil, full: false)
      @index = index
      @impact = impact
      @max_profiles = max_profiles
      @only_suites = only.to_s.split(",").map(&:strip).reject(&:empty?)
      @full = full
      @profiles = []
      @skipped = []
      @notes = []
      @suites = Set.new
      @flags = []
      build
    end

    def to_h
      {
        "changed_files" => impact.changed_files,
        "families" => families,
        "suites" => suites.to_a.sort,
        "flags" => flags,
        "profiles" => profiles,
        "skipped" => skipped,
        "notes" => notes,
        "covered" => !profiles.empty?
      }
    end

    def dispatch_command(repo_slug:, ref:, runner_arch: "x86_64", workflow: "qemu-test.yaml")
      if profiles.empty?
        raise ArgumentError, "no QEMU profiles selected"
      end

      [
        "gh", "workflow", "run", workflow,
        "-R", repo_slug,
        "--ref", ref,
        "-f", "profiles=#{profiles.map { |profile| profile['profile'] }.join(' ')}",
        "-f", "runner_arch=#{runner_arch}"
      ]
    end

    def shell
      lines = ["cd #{Shellwords.escape(index.repo.root)}", "set -eu"]
      if profiles.empty?
        lines << "echo 'No QEMU verification plan'"
      else
        profiles.each do |profile|
          lines << profile["build"]
          lines << profile["run"]
        end
      end
      lines.join("\n")
    end

    def text
      lines = ["QEMU verification plan"]
      lines << "Affected families: #{families.empty? ? 'none' : families.join(', ')}"
      if profiles.empty?
        lines << "Profiles: none"
      else
        profiles.each do |profile|
          lines << ""
          lines << "#{profile['profile']} (#{profile['family']}, #{profile['soc']})"
          lines << "  capabilities: #{profile['caps'].join(', ')}"
          lines << "  network: #{profile['net']}#{profile['requires_root'] ? ' (requires sudo)' : ''}"
          lines << "  suites: #{profile['suites'].empty? ? 'full' : profile['suites'].join(', ')}"
          lines << "  build: #{profile['build']}"
          lines << "  run: #{profile['run']}"
        end
      end
      skipped.each do |skipped_entry|
        lines << "Skipped #{skipped_entry['family']}: #{skipped_entry['reason']}"
      end
      notes.each { |note| lines << "Note: #{note}" }
      lines.join("\n")
    end

    private

    def build
      @families = affected_families
      if @families.empty?
        notes << "No affected camera family; QEMU verification is not applicable."
        return
      end

      @suites = selected_suites
      @flags << "--reboot-test" if reboot_change?

      selected_families = @full ? @families : @families.first(@max_profiles)
      (@families - selected_families).each do |family|
        skipped << { "family" => family, "reason" => "max_profiles=#{@max_profiles}" }
      end

      selected_families.each do |family|
        profile = choose_profile(family)
        if profile
          profiles << profile_entry(profile)
        else
          skipped << { "family" => family, "reason" => "no QEMU test profile" }
          notes << "Add configs/cameras-testing/<profile>/qemu-test.json to cover #{family}."
        end
      end

      unless profiles.empty?
        notes << "QEMU verifies emulated Ingenic behavior; it does not replace real-hardware validation."
        notes << "tap and slip runs need sudo and /dev/net/tun; run.sh re-execs itself when needed." if profiles.any? { |profile| profile["requires_root"] }
      end
    end

    def affected_families
      families = impact.affected_cameras.filter_map { |camera| camera["soc_family"] }.uniq
      families |= Array(impact.to_h.dig("entities", "soc_families"))
      if broad_change?
        families = @full ? index.qemu_profiles_by_family.keys.sort : (DEFAULT_FAMILIES & index.qemu_profiles_by_family.keys)
        families = index.qemu_profiles_by_family.keys.sort if families.empty?
      end
      families.sort_by do |family|
        count = impact.affected_cameras.count { |camera| camera["soc_family"] == family }
        [-count, family]
      end
    end

    def selected_suites
      return Set.new if @full
      return Set.new(@only_suites) if @only_suites.any?

      suites = Set.new
      packages = Array(impact.to_h.dig("entities", "packages"))
      changed = impact.changed_files

      webui = changed.any? { |path| webui_path?(path) } || packages.any? { |package| webui_package?(package) }
      onvif = changed.any? { |path| onvif_path?(path) } || packages.any? { |package| onvif_package?(package) }
      wifi = changed.any? { |path| wifi_path?(path) } || packages.any? { |package| wifi_package?(package) }
      usb = changed.any? { |path| usb_path?(path) } || packages.any? { |package| usb_package?(package) }
      network = changed.any? { |path| network_path?(path) } || packages.any? { |package| network_package?(package) }

      suites << "webui" if webui
      suites << "playwright" if webui
      suites << "services" if webui || network
      suites << "onvif" if onvif
      suites << "webui" if onvif
      suites << "dns" if network
      suites << "ipv6" if network
      suites << "linkflap" if network || wifi
      suites << "health" if !suites.empty? || wifi || usb
      suites << "persist" if reboot_change?
      suites
    end

    def choose_profile(family)
      candidates = Array(index.qemu_profiles_by_family[family]).filter_map { |name| index.qemu_profiles[name] }
      return nil if candidates.empty?

      required = []
      required << "wired" if wired_required?
      required << "wifi" if wifi_change?
      required << "usb" if usb_change?

      matching = candidates.select { |profile| required.all? { |capability| capability?(profile, capability) } }
      pool = matching.empty? ? candidates : matching
      chosen = pool.max_by { |profile| [profile_score(profile), profile["name"]] }
      if matching.empty? && !required.empty?
        notes << "No #{family} QEMU profile matched #{required.join(', ')}; using #{chosen['name']}."
      end
      chosen
    end

    def profile_entry(profile)
      {
        "profile" => profile["name"],
        "family" => profile["family"],
        "soc" => profile["soc"],
        "caps" => profile["caps"],
        "net" => profile["net"],
        "requires_root" => %w[tap slip].include?(profile["net"]),
        "suites" => suites.to_a.sort,
        "flags" => flags,
        "build" => build_command(profile["name"]),
        "run" => run_command(profile["name"])
      }
    end

    def build_command(profile)
      "make GROUP=testing CAMERA=#{Shellwords.escape(profile)} fast"
    end

    def run_command(profile)
      parts = ["scripts/qemu-test/run.sh", profile, "--report-dir", "qemu-reports/#{profile}"]
      parts += ["--only", suites.to_a.sort.join(",")] if suites.any?
      parts += flags
      parts.map { |part| Shellwords.escape(part) }.join(" ")
    end

    def profile_score(profile)
      capabilities = profile["caps"].size * 10
      capabilities + NET_SCORE.fetch(profile["net"], 0)
    end

    def capability?(profile, capability)
      case capability
      when "wired" then profile["caps"].include?("wired")
      when "wifi" then profile["caps"].include?("wifi")
      when "usb" then profile["caps"].any? { |cap| %w[usb_direct usb_direct_client].include?(cap) }
      else false
      end
    end

    def wired_required?
      suites.intersect?(Set.new(%w[webui onvif services dns ipv6 linkflap]))
    end

    def wifi_change?
      impact.changed_files.any? { |path| wifi_path?(path) } ||
        Array(impact.to_h.dig("entities", "packages")).any? { |package| wifi_package?(package) }
    end

    def usb_change?
      impact.changed_files.any? { |path| usb_path?(path) } ||
        Array(impact.to_h.dig("entities", "packages")).any? { |package| usb_package?(package) }
    end

    def reboot_change?
      impact.changed_files.any? do |path|
        path.start_with?("overlay/") ||
          path.include?("sysupgrade") ||
          path.include?("persist")
      end
    end

    def broad_change?
      return false if index.cameras.empty?
      return true if impact.global

      families = impact.affected_cameras.filter_map { |camera| camera["soc_family"] }.uniq
      families.size > 1 && impact.affected_cameras.size.to_f / index.cameras.size >= BROAD_CHANGE_RATIO
    end

    def webui_path?(path)
      path.match?(%r{(?:\A|/)package/thingino-webui/}) ||
        path.end_with?(".webui.json") ||
        path.match?(/\.(?:cgi|js|html|css)\z/)
    end

    def webui_package?(package)
      package == "thingino-webui" || index.packages.dig(package, "plugin_files")&.any?
    end

    def onvif_path?(path)
      path.include?("onvif")
    end

    def onvif_package?(package)
      %w[thingino-onvif prudynt-t thingino-raptor thingino-raptor-common thingino-raptor-hal thingino-raptor-ipc strero timps thingino-streamer].include?(package)
    end

    def wifi_path?(path)
      path.include?("wpa_supplicant") || path.include?("wireless") || path.include?("wlan") || path.include?("portal")
    end

    def wifi_package?(package)
      package == "wifi" || package.start_with?("wifi-")
    end

    def usb_path?(path)
      path.match?(%r{(?:\A|/)usb}) || path.include?("gadget")
    end

    def usb_package?(package)
      %w[usbnet gadget-serial].include?(package)
    end

    def network_path?(path)
      path.start_with?("overlay/etc/init.d/") ||
        path.match?(%r{/(?:S40network|S05dns|S49ntpd|S50dropbear|S52netwatch|S90httpd|S91mqttsub)})
    end

    def network_package?(package)
      %w[thingino-ethernet thingino-netwatch thingino-vpn thingino-tailscale zerotier-one].include?(package)
    end
  end
end
