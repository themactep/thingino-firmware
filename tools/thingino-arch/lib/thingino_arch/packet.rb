require "json"

module ThinginoArch
  class Packet
    def initialize(index:, impact:, verification: nil, qemu_results: nil, findings:, brief:, prompt:, diff:, diff_stat:, title: nil, max_cameras: 40, max_diff_bytes: 200_000)
      @index = index
      @impact = impact
      @verification = verification
      @qemu_results = qemu_results
      @findings = findings
      @brief = brief
      @prompt = prompt
      @diff = diff
      @diff_stat = diff_stat
      @title = title
      @max_cameras = max_cameras
      @max_diff_bytes = max_diff_bytes
    end

    def render
      lines = []
      lines << "# Thingino architecture review packet"
      lines << ""
      lines << "## Change"
      lines << ""
      lines << "- Repository: `#{@index.repo.root}`"
      lines << "- Head: `#{@index.repo.head}`"
      lines << "- Title: #{@title}" unless @title.to_s.empty?
      lines << "- Changed files: #{@impact.changed_files.size}"
      lines << "- Affected camera profiles: #{@impact.affected_cameras.size}"
      lines << ""
      lines << "```"
      lines << @diff_stat.to_s.strip
      lines << "```"
      lines << ""

      lines << "## Impact"
      lines << ""
      lines << "```"
      lines << @impact.summary
      lines << "```"
      lines << ""

      lines.concat(affected_cameras_section)
      lines.concat(entities_section)
      lines.concat(verification_section)
      lines.concat(qemu_results_section)
      lines.concat(findings_section)
      lines.concat(relevant_index_section)
      lines.concat(brief_section)
      lines.concat(prompt_section)
      lines.concat(diff_section)
      lines.join("\n")
    end

    private

    def affected_cameras_section
      lines = []
      cameras = @impact.affected_cameras
      return lines if cameras.empty?

      lines << "### Affected camera profiles"
      lines << ""
      lines << "| Profile | SoC | Sensors | Wi-Fi | Reasons |"
      lines << "| --- | --- | --- | --- | --- |"
      cameras.first(@max_cameras).each do |camera|
        lines << "| `#{camera['id']}` | #{camera['soc_family']} | #{Array(camera['sensors']).join(', ')} | #{Array(camera['wifi']).join(', ')} | #{Array(camera['reasons']).join('<br>')} |"
      end
      remaining = cameras.size - @max_cameras
      lines << ""
      lines << "_#{remaining} more profiles omitted._" if remaining.positive?
      lines << ""
      lines
    end

    def entities_section
      lines = []
      entities = @impact.to_h["entities"]
      interesting = entities.reject { |name, values| values.empty? || %w[tooling other].include?(name) }
      return lines if interesting.empty?

      lines << "### Affected entities"
      lines << ""
      interesting.each do |name, values|
        lines << "- **#{name}**: #{values.map { |value| "`#{value}`" }.join(', ')}"
      end
      lines << ""
      lines
    end

    def verification_section
      return [] unless @verification

      payload = @verification.to_h
      return [] if payload["profiles"].empty? && payload["skipped"].empty?

      lines = ["### Verification plan", ""]
      lines << "```"
      lines << @verification.text
      lines << "```"
      lines << ""
      lines << "```sh"
      lines << @verification.shell
      lines << "```"
      lines << ""
      lines
    end

    def qemu_results_section
      return [] unless @qemu_results

      ["### QEMU results", "", "```", @qemu_results.text, "```", ""]
    end

    def findings_section
      lines = []
      errors = @findings.select { |finding| finding.severity == "error" }
      warnings = @findings.select { |finding| finding.severity == "warning" }
      infos = @findings.select { |finding| finding.severity == "info" }
      return lines if @findings.empty?

      lines << "### Deterministic structural findings"
      lines << ""
      lines << "Errors: #{errors.size}, warnings: #{warnings.size}, info: #{infos.size}"
      lines << ""
      lines << "| Severity | Rule | Path | Message |"
      lines << "| --- | --- | --- | --- |"
      (@findings.first(80)).each do |finding|
        lines << "| #{finding.severity} | `#{finding.id}` | `#{finding.path}` | #{finding.message.gsub('|', '\\|')} |"
      end
      lines << ""
      lines << "_#{@findings.size - 80} more findings omitted._" if @findings.size > 80
      lines << ""
      lines
    end

    def relevant_index_section
      lines = []
      package_names = @impact.to_h["entities"]["packages"]
      camera_ids = @impact.to_h["entities"]["cameras"]
      plugin_names = @impact.to_h["entities"]["plugins"]
      init_names = @impact.to_h["entities"]["init_scripts"]

      packages = package_names.filter_map { |name| @index.packages[name] }
      cameras = camera_ids.filter_map { |id| @index.cameras[id] }
      plugins = @index.plugins.select { |plugin| plugin_names.include?(plugin["name"]) }
      init_scripts = @index.init_scripts.select { |script| init_names.include?(script["basename"]) }
      family_names = @impact.to_h["entities"]["soc_families"]
      families = family_names.filter_map { |name| @index.soc_families[name] }
      fragment_names = @impact.to_h["entities"]["fragments"]
      fragments = fragment_names.filter_map { |name| @index.fragments[name] }
      wifi_drivers = @index.wifi_drivers.values.select do |driver|
        package_names.include?("wifi") || package_names.include?(driver["package"])
      end

      return lines if packages.empty? && cameras.empty? && plugins.empty? && init_scripts.empty? && families.empty? && fragments.empty? && wifi_drivers.empty?

      lines << "### Relevant architecture index"
      lines << ""
      unless packages.empty?
        lines << "#### Packages"
        lines << ""
        lines << "```json"
        lines << JSON.pretty_generate(packages)
        lines << "```"
        lines << ""
      end

      pinned = packages.select { |package| !package["site"].to_s.empty? && !package["version"].to_s.empty? }
      unless pinned.empty?
        lines << "#### Component pins"
        lines << ""
        lines << "| Package | Site | Version |"
        lines << "| --- | --- | --- |"
        pinned.each do |package|
          lines << "| `#{package['name']}` | #{package['site']} | `#{package['version']}` |"
        end
        lines << ""
        lines << "Fetch these repositories at the pinned versions before claiming cross-repo compatibility."
        lines << ""
      end

      unless cameras.empty?
        lines << "#### Camera profiles"
        lines << ""
        lines << "```json"
        lines << JSON.pretty_generate(cameras.first(@max_cameras))
        lines << "```"
        lines << ""
      end

      unless plugins.empty?
        lines << "#### WebUI plugins"
        lines << ""
        lines << "```json"
        lines << JSON.pretty_generate(plugins)
        lines << "```"
        lines << ""
      end

      unless init_scripts.empty?
        lines << "#### Init scripts"
        lines << ""
        lines << "```json"
        lines << JSON.pretty_generate(init_scripts)
        lines << "```"
        lines << ""
      end

      unless wifi_drivers.empty?
        lines << "#### WiFi drivers"
        lines << ""
        lines << "```json"
        lines << JSON.pretty_generate(wifi_drivers)
        lines << "```"
        lines << ""
      end

      unless families.empty?
        lines << "#### SoC families"
        lines << ""
        lines << "```json"
        lines << JSON.pretty_generate(families)
        lines << "```"
        lines << ""
      end

      unless fragments.empty?
        lines << "#### Fragments"
        lines << ""
        lines << "```json"
        lines << JSON.pretty_generate(fragments)
        lines << "```"
        lines << ""
      end

      lines
    end

    def brief_section
      return [] if @brief.to_s.empty?

      ["## Architecture brief", "", @brief.strip, ""]
    end

    def prompt_section
      return [] if @prompt.to_s.empty?

      ["## Review instructions", "", @prompt.strip, ""]
    end

    def diff_section
      lines = ["## Diff", "", "```diff"]
      diff = @diff.to_s
      if diff.bytesize > @max_diff_bytes
        lines << diff.byteslice(0, @max_diff_bytes)
        lines << ""
        lines << "[diff truncated at #{@max_diff_bytes} bytes]"
      else
        lines << diff
      end
      lines << "```"
      lines << ""
      lines
    end
  end
end
