require "fileutils"
require "json"
require "open3"
require "optparse"
require "set"

module ThinginoArch
  class CLI
    ROOT = File.expand_path("../..", __dir__)
    DEFAULT_BRIEF = File.join(ROOT, "architecture", "thingino.md")
    DEFAULT_PROMPT = File.join(ROOT, "prompts", "architecture-review.md")
    DEFAULT_BASELINE = ".thingino-arch/baseline.json"

    def run(argv)
      command = argv.shift
      case command
      when "index" then index(argv)
      when "impact" then impact(argv)
      when "verify" then verify(argv)
      when "check" then check(argv)
      when "packet" then packet(argv)
      when "version", "--version", "-v" then puts VERSION
      when "help", "--help", "-h", nil then puts usage
      else
        warn "unknown command: #{command}"
        warn usage
        exit 2
      end
    rescue OptionParser::ParseError => error
      warn error.message
      exit 2
    end

    private

    def index(argv)
      options = {}
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: thingino-arch index [--repo PATH] [--output FILE]"
        opts.on("--repo PATH", "Thingino firmware checkout") { |value| options[:repo] = value }
        opts.on("--output FILE", "Write JSON to FILE instead of stdout") { |value| options[:output] = value }
      end
      parser.parse!(argv)

      repo = build_repo(options)
      data = Index.new(repo).to_h
      payload = JSON.pretty_generate(data)
      if options[:output]
        write_file(options[:output], payload + "\n")
        warn "indexed #{data['stats']['packages']} packages, #{data['stats']['cameras']} cameras, #{data['stats']['wifi_drivers']} Wi-Fi drivers -> #{options[:output]}"
      else
        puts payload
      end
    end

    def impact(argv)
      options = { format: "text" }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: thingino-arch impact [--repo PATH] [--from REF] [--to REF] [--files LIST] [--format json|text] [--output FILE]"
        opts.on("--repo PATH", "Thingino firmware checkout") { |value| options[:repo] = value }
        opts.on("--from REF", "Base ref") { |value| options[:from] = value }
        opts.on("--to REF", "Head ref") { |value| options[:to] = value }
        opts.on("--files LIST", "Comma-separated changed files") { |value| options[:files] = value }
        opts.on("--format FORMAT", "json or text") { |value| options[:format] = value }
        opts.on("--output FILE", "Write output to FILE") { |value| options[:output] = value }
      end
      parser.parse!(argv)

      repo = build_repo(options)
      index = Index.new(repo)
      changed = changed_files(repo, options)
      report = Impact.new(index, changed)
      output = if options[:format] == "json"
                 JSON.pretty_generate(report.to_h)
               else
                 impact_text(report)
               end
      if options[:output]
        write_file(options[:output], output + "\n")
      else
        puts output
      end
    end

    def verify(argv)
      options = { format: "text" }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: thingino-arch verify [--repo PATH] [--from REF] [--to REF] [--files LIST] [--format json|text|shell] [--only SUITES] [--max-profiles N] [--full] [--dispatch] [--ref REF] [--runner-arch ARCH] [--github-repo OWNER/REPO] [--workflow FILE] [--output FILE]"
        opts.on("--repo PATH", "Thingino firmware checkout") { |value| options[:repo] = value }
        opts.on("--from REF", "Base ref") { |value| options[:from] = value }
        opts.on("--to REF", "Head ref") { |value| options[:to] = value }
        opts.on("--files LIST", "Comma-separated changed files") { |value| options[:files] = value }
        opts.on("--format FORMAT", "json, text, or shell") { |value| options[:format] = value }
        opts.on("--only SUITES", "Comma-separated optional QEMU suites") { |value| options[:only] = value }
        opts.on("--max-profiles N", Integer, "Maximum QEMU profiles") { |value| options[:max_profiles] = value }
        opts.on("--full", "Run full suites for every affected family") { options[:full] = true }
        opts.on("--dispatch", "Dispatch the native qemu-test workflow") { options[:dispatch] = true }
        opts.on("--ref REF", "Branch or tag to dispatch on") { |value| options[:ref] = value }
        opts.on("--runner-arch ARCH", "QEMU workflow build architecture") { |value| options[:runner_arch] = value }
        opts.on("--github-repo OWNER/REPO", "GitHub repository override") { |value| options[:github_repo] = value }
        opts.on("--workflow FILE", "Workflow file to dispatch") { |value| options[:workflow] = value }
        opts.on("--output FILE", "Write output to FILE") { |value| options[:output] = value }
      end
      parser.parse!(argv)

      if options[:dispatch] && options[:only].to_s.split(",").map(&:strip).reject(&:empty?).any?
        warn "--dispatch uses the native qemu-test workflow, which does not accept --only"
        return 2
      end

      repo = build_repo(options)
      index = Index.new(repo)
      changed = changed_files(repo, options)
      report = Impact.new(index, changed)
      verification = Verification.new(
        index,
        report,
        max_profiles: options[:max_profiles] || Verification::DEFAULT_MAX_PROFILES,
        only: options[:only],
        full: options[:full]
      )

      if options[:dispatch]
        return dispatch_verification(repo, verification, options)
      end

      output = case options[:format]
               when "json" then JSON.pretty_generate(verification.to_h)
               when "shell" then verification.shell
               else verification.text
               end
      if options[:output]
        write_file(options[:output], output + "\n")
      else
        puts output
      end
    end

    def dispatch_verification(repo, verification, options)
      if verification.profiles.empty?
        warn "no QEMU profiles selected; nothing to dispatch"
        return 1
      end

      slug = options[:github_repo] || repo.github_slug
      unless slug
        warn "cannot determine GitHub repository; pass --github-repo OWNER/REPO"
        return 1
      end

      ref = options[:ref]
      unless ref
        current = repo.git("rev-parse", "--abbrev-ref", "HEAD").strip
        ref = current unless current == "HEAD"
      end
      unless ref
        warn "a branch ref is required; pass --ref BRANCH"
        return 1
      end

      runner_arch = options[:runner_arch] || "x86_64"
      workflow = options[:workflow] || "qemu-test.yaml"
      command = verification.dispatch_command(
        repo_slug: slug,
        ref: ref,
        runner_arch: runner_arch,
        workflow: workflow
      )

      stdout, stderr, status = Open3.capture3(*command)
      unless status.success?
        warn stderr.strip
        return 1
      end

      puts stdout unless stdout.strip.empty?
      puts "Dispatched #{workflow} on #{slug}@#{ref}"
      puts "Profiles: #{verification.profiles.map { |profile| profile['profile'] }.join(' ')}"
      puts "Runner arch: #{runner_arch}"
      puts "The native workflow runs the full QEMU suite; suite selection is not supported in dispatch mode."
      0
    rescue Errno::ENOENT
      warn "gh is required to dispatch the native QEMU workflow"
      1
    end

    def check(argv)
      options = { format: "text" }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: thingino-arch check [--repo PATH] [--from REF] [--to REF] [--files LIST] [--changed] [--baseline FILE] [--write-baseline [FILE]] [--strict] [--format json|text]"
        opts.on("--repo PATH", "Thingino firmware checkout") { |value| options[:repo] = value }
        opts.on("--from REF", "Base ref") { |value| options[:from] = value }
        opts.on("--to REF", "Head ref") { |value| options[:to] = value }
        opts.on("--files LIST", "Comma-separated changed files") { |value| options[:files] = value }
        opts.on("--changed", "Report only findings in the changed scope") { options[:changed] = true }
        opts.on("--baseline FILE", "Baseline findings file") { |value| options[:baseline] = value }
        opts.on("--write-baseline [FILE]", "Write current findings as the baseline") { |value| options[:write_baseline] = value || true }
        opts.on("--strict", "Fail on warnings as well as errors") { options[:strict] = true }
        opts.on("--format FORMAT", "json or text") { |value| options[:format] = value }
      end
      parser.parse!(argv)

      repo = build_repo(options)
      index = Index.new(repo)
      findings = Checks.new(index).run

      if options[:write_baseline]
        path = baseline_path(repo, options[:write_baseline])
        Baseline.write(path, findings)
        warn "wrote #{findings.size} findings to #{path}"
        return 0
      end

      baseline = Baseline.load(baseline_path(repo, options[:baseline]))
      baselined = findings.count { |finding| baseline.include?(finding.fingerprint) }
      findings = findings.reject { |finding| baseline.include?(finding.fingerprint) }

      if options[:changed]
        changed = changed_files(repo, options)
        findings = filter_changed(findings, changed, index)
      end

      print_findings(findings, baselined, options[:format])
      exit_code(findings, options[:strict])
    end

    def packet(argv)
      options = { format: "markdown" }
      parser = OptionParser.new do |opts|
        opts.banner = "Usage: thingino-arch packet [--repo PATH] [--from REF] [--to REF] [--title TITLE] [--output FILE] [--brief FILE] [--prompt FILE] [--max-cameras N] [--max-qemu-profiles N] [--qemu-run RUN_ID] [--github-repo OWNER/REPO] [--max-diff-bytes N] [--all-findings]"
        opts.on("--repo PATH", "Thingino firmware checkout") { |value| options[:repo] = value }
        opts.on("--from REF", "Base ref") { |value| options[:from] = value }
        opts.on("--to REF", "Head ref") { |value| options[:to] = value }
        opts.on("--files LIST", "Comma-separated changed files") { |value| options[:files] = value }
        opts.on("--title TITLE", "Change title") { |value| options[:title] = value }
        opts.on("--output FILE", "Write packet to FILE") { |value| options[:output] = value }
        opts.on("--brief FILE", "Architecture brief") { |value| options[:brief] = value }
        opts.on("--prompt FILE", "Review prompt") { |value| options[:prompt] = value }
        opts.on("--max-cameras N", Integer, "Camera rows to include") { |value| options[:max_cameras] = value }
        opts.on("--max-qemu-profiles N", Integer, "QEMU profiles to include") { |value| options[:max_qemu_profiles] = value }
        opts.on("--qemu-run RUN_ID", "Include QEMU results from a workflow run") { |value| options[:qemu_run] = value }
        opts.on("--github-repo OWNER/REPO", "GitHub repository override") { |value| options[:github_repo] = value }
        opts.on("--max-diff-bytes N", Integer, "Diff byte cap") { |value| options[:max_diff_bytes] = value }
        opts.on("--baseline FILE", "Baseline findings file") { |value| options[:baseline] = value }
        opts.on("--all-findings", "Include baselined findings and ignore the changed scope") { options[:all_findings] = true }
      end
      parser.parse!(argv)

      repo = build_repo(options)
      index = Index.new(repo)
      changed = changed_files(repo, options)
      report = Impact.new(index, changed)
      verification = Verification.new(
        index,
        report,
        max_profiles: options[:max_qemu_profiles] || Verification::DEFAULT_MAX_PROFILES
      )
      findings = Checks.new(index).run
      unless options[:all_findings]
        baseline = Baseline.load(baseline_path(repo, options[:baseline]))
        findings = findings.reject { |finding| baseline.include?(finding.fingerprint) }
        findings = filter_changed(findings, changed, index)
      end
      from, to = range(options)
      qemu_results = if options[:qemu_run]
                       QemuResults.new(
                         repo: repo,
                         run_id: options[:qemu_run],
                         repo_slug: options[:github_repo] || repo.github_slug,
                         profiles: verification.profiles.map { |profile| profile["profile"] }
                       )
                     end
      brief = read_optional(options[:brief] || DEFAULT_BRIEF)
      prompt = read_optional(options[:prompt] || DEFAULT_PROMPT)
      packet = Packet.new(
        index: index,
        impact: report,
        verification: verification,
        qemu_results: qemu_results,
        findings: findings,
        brief: brief,
        prompt: prompt,
        diff: repo.diff_text(from, to),
        diff_stat: repo.diff_stat(from, to),
        title: options[:title],
        max_cameras: options[:max_cameras] || 40,
        max_diff_bytes: options[:max_diff_bytes] || 200_000
      ).render

      if options[:output]
        write_file(options[:output], packet + "\n")
        warn "wrote review packet -> #{options[:output]}"
      else
        puts packet
      end
    end

    def build_repo(options)
      Repo.new(options[:repo] || ENV["THINGINO_REPO"] || Dir.pwd)
    end

    def changed_files(repo, options)
      return options[:files].split(",").map(&:strip).reject(&:empty?) if options[:files]

      from, to = range(options)
      repo.changed_files(from, to)
    end

    def range(options)
      [options[:from] || "HEAD~1", options[:to] || "HEAD"]
    end

    def baseline_path(repo, option)
      return File.join(repo.root, DEFAULT_BASELINE) if option.nil? || option == true

      option
    end

    def filter_changed(findings, changed, index)
      prefixes = Set.new
      entities = Set.new
      changed.each do |path|
        case path
        when %r{\A(package/[^/]+/)}
          prefixes << Regexp.last_match(1)
          entities << Regexp.last_match(1).split("/")[1]
        when %r{\A(configs/cameras[^/]*/([^/]+)/)}
          prefix = Regexp.last_match(0)
          prefixes << prefix
          camera = index.cameras.values.find { |entry| entry["dir"] == prefix.chomp("/") }
          entities << camera["id"] if camera
        when %r{\Aconfigs/fragments/(.+)\z}
          prefixes << path
          entities << File.basename(Regexp.last_match(1), ".fragment")
        when %r{\Asoc/[^/]+/([^/]+)\.mk\z}
          prefixes << path
          entities << Regexp.last_match(1)
        else
          prefixes << path
        end
      end

      findings.select do |finding|
        prefixes.any? { |prefix| finding.path == prefix || finding.path.start_with?(prefix) } ||
          entities.include?(finding.entity)
      end
    end

    def print_findings(findings, baselined, format)
      errors = findings.count { |finding| finding.severity == "error" }
      warnings = findings.count { |finding| finding.severity == "warning" }
      infos = findings.count { |finding| finding.severity == "info" }

      if format == "json"
        puts JSON.pretty_generate(
          "findings" => findings.map(&:to_h),
          "summary" => {
            "errors" => errors,
            "warnings" => warnings,
            "info" => infos,
            "baselined" => baselined,
            "total" => findings.size
          }
        )
        return
      end

      findings.each do |finding|
        location = finding.path.to_s.empty? ? finding.entity : finding.path
        puts "#{finding.severity.upcase} [#{finding.id}] #{location}: #{finding.message}"
      end
      puts "Summary: #{errors} errors, #{warnings} warnings, #{infos} info, #{baselined} baselined"
    end

    def exit_code(findings, strict)
      errors = findings.count { |finding| finding.severity == "error" }
      warnings = findings.count { |finding| finding.severity == "warning" }
      return 1 if errors.positive?
      return 1 if strict && warnings.positive?

      0
    end

    def impact_text(report)
      lines = [report.summary]
      unless report.affected_cameras.empty?
        lines << ""
        lines << "Affected cameras:"
        report.affected_cameras.first(60).each do |camera|
          lines << "  #{camera['id']} (#{camera['reasons'].join(', ')})"
        end
        remaining = report.affected_cameras.size - 60
        lines << "  ... #{remaining} more" if remaining.positive?
      end
      lines.join("\n")
    end

    def read_optional(path)
      return "" unless path && File.file?(path)

      File.read(path)
    end

    def write_file(path, content)
      directory = File.dirname(path)
      FileUtils.mkdir_p(directory) unless directory == "."
      File.write(path, content)
    end

    def usage
      <<~TEXT
        thingino-arch #{VERSION}

        Usage:
          thingino-arch index   [--repo PATH] [--output FILE]
          thingino-arch impact  [--repo PATH] [--from REF] [--to REF] [--files LIST] [--format json|text]
          thingino-arch verify  [--repo PATH] [--from REF] [--to REF] [--files LIST] [--format json|text|shell] [--only SUITES] [--max-profiles N] [--full] [--dispatch] [--ref REF]
          thingino-arch check   [--repo PATH] [--from REF] [--to REF] [--files LIST] [--changed] [--baseline FILE] [--write-baseline [FILE]] [--strict]
          thingino-arch packet  [--repo PATH] [--from REF] [--to REF] [--title TITLE] [--output FILE]

        Environment:
          THINGINO_REPO   Default Thingino firmware checkout
      TEXT
    end
  end
end
