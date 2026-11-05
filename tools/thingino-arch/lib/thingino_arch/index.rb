require "json"
require "set"

module ThinginoArch
  class Index
    attr_reader :repo, :packages, :config_symbols, :config_sources, :wifi_drivers,
                :wifi_packages, :soc_models, :soc_families, :soc_model_conflicts,
                :kernels, :fragments, :cameras, :init_scripts, :plugins, :choices,
                :cameras_by_package, :cameras_by_family, :cameras_by_vendor,
                :cameras_by_fragment, :cameras_by_wifi, :init_by_basename,
                :profiles_without_defconfig, :reachable_config_files,
                :qemu_profiles, :qemu_profiles_by_family

    def initialize(repo)
      @repo = repo
      @packages = {}
      @config_symbols = {}
      @config_sources = []
      @choices = []
      @wifi_drivers = {}
      @wifi_packages = {}
      @soc_models = {}
      @soc_families = {}
      @soc_model_conflicts = []
      @kernels = {}
      @fragments = {}
      @cameras = {}
      @init_scripts = []
      @plugins = []
      @cameras_by_package = Hash.new { |hash, key| hash[key] = [] }
      @cameras_by_family = Hash.new { |hash, key| hash[key] = [] }
      @cameras_by_vendor = Hash.new { |hash, key| hash[key] = [] }
      @cameras_by_fragment = Hash.new { |hash, key| hash[key] = [] }
      @cameras_by_wifi = Hash.new { |hash, key| hash[key] = [] }
      @init_by_basename = Hash.new { |hash, key| hash[key] = [] }
      @profiles_without_defconfig = []
      @reachable_config_files = Set.new
      @qemu_profiles = {}
      @qemu_profiles_by_family = Hash.new { |hash, key| hash[key] = [] }
      build
    end

    def build
      parse_packages
      parse_config_symbols
      parse_config_sources
      compute_config_reachability
      attach_package_symbols
      parse_wifi
      parse_soc
      parse_kernels
      parse_fragments
      parse_qemu_profiles
      parse_cameras
      parse_init_scripts
      parse_plugins
      attach_reverse_maps
    end

    def to_h
      {
        "repo" => repo.root,
        "head" => repo.head,
        "generated_at" => Time.now.utc.iso8601,
        "packages" => packages,
        "config" => {
          "symbols" => config_symbols,
          "sources" => config_sources,
          "choices" => choices,
          "reachable_files" => reachable_config_files.to_a.sort
        },
        "wifi" => {
          "drivers" => wifi_drivers,
          "packages" => wifi_packages
        },
        "soc" => {
          "models" => soc_models,
          "families" => soc_families,
          "conflicts" => soc_model_conflicts
        },
        "kernels" => kernels,
        "fragments" => fragments,
        "qemu_profiles" => qemu_profiles,
        "cameras" => cameras,
        "init_scripts" => init_scripts,
        "plugins" => plugins,
        "reverse" => {
          "cameras_by_package" => cameras_by_package,
          "cameras_by_family" => cameras_by_family,
          "cameras_by_vendor" => cameras_by_vendor,
          "cameras_by_fragment" => cameras_by_fragment,
          "cameras_by_wifi" => cameras_by_wifi,
          "qemu_profiles_by_family" => qemu_profiles_by_family
        },
        "profiles_without_defconfig" => profiles_without_defconfig,
        "stats" => {
          "packages" => packages.size,
          "config_symbols" => config_symbols.size,
          "wifi_drivers" => wifi_drivers.size,
          "soc_models" => soc_models.size,
          "cameras" => cameras.size,
          "fragments" => fragments.size,
          "init_scripts" => init_scripts.size,
          "plugins" => plugins.size,
          "qemu_profiles" => qemu_profiles.size
        }
      }
    end

    private

    def parse_packages
      repo.dirs("package/*").each do |absolute|
        name = File.basename(absolute)
        next if name == "all-patches"

        mk_files = repo.glob("package/#{name}/*.mk").map { |path| repo.relative(path) }
        config_files = repo.glob("package/#{name}/Config*.in").map { |path| repo.relative(path) }
        hash_files = repo.glob("package/#{name}/*.hash").map { |path| repo.relative(path) }
        patch_files = repo.glob("package/#{name}/**/*.patch").map { |path| repo.relative(path) }
        plugin_files = repo.glob("package/#{name}/**/*.webui.json").map { |path| repo.relative(path) }
        init_files = (repo.glob("package/#{name}/files/**/S[0-9]*") +
                      repo.glob("package/#{name}/files/**/K[0-9]*")).map { |path| repo.relative(path) }.uniq

        vars = make_vars(mk_files)
        prefix = choose_prefix(name, vars)
        site = value(vars, "#{prefix}_SITE")
        site_method = value(vars, "#{prefix}_SITE_METHOD")
        dependencies = vars["#{prefix}_DEPENDENCIES"].flat_map { |entry| entry.split(/\s+/) }
                                                .reject { |entry| entry.empty? || entry.include?("$(") }
                                                .uniq

        packages[name] = {
          "name" => name,
          "dir" => "package/#{name}",
          "mk_files" => mk_files,
          "config_files" => config_files,
          "hash_files" => hash_files,
          "patches" => patch_files,
          "plugin_files" => plugin_files,
          "init_files" => init_files,
          "variable_prefix" => prefix,
          "version" => value(vars, "#{prefix}_VERSION"),
          "site" => site,
          "site_method" => site_method,
          "license" => value(vars, "#{prefix}_LICENSE"),
          "dependencies" => dependencies,
          "has_hash" => !hash_files.empty?,
          "local" => site_method == "local" || site.to_s.include?("BR2_EXTERNAL") || site.to_s.include?("CAMERA_SUBDIR"),
          "remote" => remote_site?(site, site_method),
          "symbols" => [],
          "module_name" => nil,
          "module_opts" => nil
        }
      end
    end

    def parse_config_symbols
      config_files.each do |relative|
        current = nil
        in_choice = false
        choice_symbols = []
        choice_default = nil

        repo.read(relative).each_line do |line|
          if (match = line.match(/^\s*choice\b/))
            in_choice = true
            choice_symbols = []
            choice_default = nil
          elsif in_choice && (match = line.match(/^\s*endchoice\b/))
            choices << { "file" => relative, "symbols" => choice_symbols, "default" => choice_default } unless choice_symbols.empty?
            in_choice = false
            choice_symbols = []
            choice_default = nil
          elsif in_choice && (match = line.match(/^\s*default\s+(BR2_[A-Z0-9_]+)/))
            choice_default = match[1]
          elsif (match = line.match(/^\s*(?:menuconfig|config)\s+(BR2_[A-Z0-9_]+)/))
            current = match[1]
            choice_symbols << current if in_choice
            config_symbols[current] ||= {
              "name" => current,
              "file" => relative,
              "package" => package_for(relative),
              "selects" => [],
              "depends" => [],
              "defaults" => []
            }
          elsif current && (match = line.match(/^\s*select\s+(BR2_[A-Z0-9_]+)/))
            config_symbols[current]["selects"] << match[1]
          elsif current && (match = line.match(/^\s*depends on\s+(.+?)\s*$/))
            config_symbols[current]["depends"] << match[1]
          elsif current && (match = line.match(/^\s*default\s+(y|n)\b/))
            config_symbols[current]["defaults"] << match[1]
          end
        end
      end
    end

    def parse_config_sources
      config_files.each do |relative|
        repo.read(relative).each_line do |line|
          match = line.match(/^\s*source\s+(.+?)\s*$/)
          next unless match

          target = normalize_source(match[1], relative)
          config_sources << { "from" => relative, "to" => target, "raw" => match[1].strip }
        end
      end
    end

    def compute_config_reachability
      adjacency = Hash.new { |hash, key| hash[key] = [] }
      config_sources.each do |edge|
        adjacency[edge["from"]] << edge["to"] if edge["to"]
      end

      seen = Set.new
      queue = config_files.reject { |file| file.start_with?("package/") }
      until queue.empty?
        file = queue.shift
        next if seen.include?(file)

        seen << file
        adjacency[file].each { |target| queue << target unless seen.include?(target) }
      end
      @reachable_config_files = seen
    end

    def attach_package_symbols
      symbols_by_file = config_symbols.values.group_by { |entry| entry["file"] }
      @main_symbol_to_package = {}
      packages.each_value do |package|
        package["symbols"] = config_symbols.select { |_name, entry| entry["package"] == package["name"] }.keys.sort
        package["main_symbols"] = package["config_files"].reject { |file| file.end_with?(".conf", ".host") }.filter_map do |file|
          symbols_by_file[file]&.first&.dig("name")
        end.uniq
        package["main_symbols"].each { |symbol| @main_symbol_to_package[symbol] = package["name"] }
      end
    end

    def parse_wifi
      relative = "package/wifi/wifi.mk"
      return unless repo.exist?(relative)

      vars = make_vars([relative])
      repo.read(relative).each_line do |line|
        next unless line.include?("WIFI_ADD_DRIVER,")

        args = parse_make_call(line.split("WIFI_ADD_DRIVER,", 2).last)
        next unless args.size >= 3

        symbol = args[0].strip
        package = config_symbols.dig(symbol, "package") || infer_wifi_package(symbol)
        driver = {
          "symbol" => symbol,
          "package" => package,
          "module" => args[1].strip,
          "interface" => resolve_make_value(args[2].strip, vars),
          "module_name" => nil,
          "module_opts" => nil,
          "registered" => true
        }
        wifi_drivers[symbol] = driver
      end

      packages.each do |name, package|
        next unless name.start_with?("wifi-")

        vars = make_vars(package["mk_files"])
        name_key = vars.keys.find { |key| key.end_with?("_MODULE_NAME") }
        opts_key = vars.keys.find { |key| key.end_with?("_MODULE_OPTS") }
        package["module_name"] = resolve_make_value(vars[name_key].last, vars) if name_key
        package["module_opts"] = resolve_make_value(vars[opts_key].last, vars) if opts_key
        wifi_packages[name] = package
      end

      wifi_drivers.each_value do |driver|
        package = packages[driver["package"]]
        next unless package

        driver["module_name"] = package["module_name"]
        driver["module_opts"] = package["module_opts"]
      end
    end

    def parse_soc
      repo.glob("soc/*/*.mk").each do |absolute|
        relative = repo.relative(absolute)
        parts = relative.split("/")
        vendor = parts[1]
        text = repo.read(relative)
        family = text[/^\s*SOC_FAMILY\s*:?=\s*(\S+)/, 1]
        arch = text[/^\s*SOC_ARCH\s*:?=\s*(\S+)/, 1]
        models = text.scan(/filter\s+\$\(SOC_MODEL\),([^)]*)\)/).flat_map { |match| match[0].split }
        next if family.nil? || models.empty?

        soc_families[family] ||= {
          "family" => family,
          "vendor" => vendor,
          "file" => relative,
          "arch" => arch,
          "models" => []
        }
        soc_families[family]["models"] |= models

        models.each do |model|
          existing = soc_models[model]
          if existing && existing["family"] != family
            soc_model_conflicts << { "model" => model, "first" => existing, "second" => { "family" => family, "vendor" => vendor, "file" => relative } }
          else
            soc_models[model] = {
              "model" => model,
              "family" => family,
              "vendor" => vendor,
              "file" => relative,
              "arch" => arch
            }
          end
        end
      end
    end

    def parse_kernels
      repo.glob("kernels/*.mk").each do |absolute|
        relative = repo.relative(absolute)
        vendor = File.basename(relative, ".mk")
        text = repo.read(relative)
        families = text.scan(/SOC_FAMILY\),([a-z0-9]+)/).flatten.uniq
        kernels[vendor] = {
          "vendor" => vendor,
          "file" => relative,
          "families" => families
        }
      end
    end

    def parse_fragments
      repo.glob("configs/fragments/**/*.fragment").each do |absolute|
        relative = repo.relative(absolute)
        name = File.basename(relative, ".fragment")
        fragments[name] = {
          "name" => name,
          "path" => relative,
          "symbols" => parse_assignments(repo.read(relative))
        }
      end
    end

    def parse_qemu_profiles
      repo.glob("configs/cameras-testing/*/qemu-test.json").each do |absolute|
        relative = repo.relative(absolute)
        directory = File.dirname(relative)
        name = File.basename(directory)
        manifest = parse_json(repo.read(relative))
        soc_model = manifest["soc"]
        soc = soc_models[soc_model]
        qemu_profiles[name] = {
          "name" => name,
          "dir" => directory,
          "manifest" => relative,
          "soc" => soc_model,
          "family" => soc && soc["family"],
          "vendor" => soc && soc["vendor"],
          "caps" => Array(manifest["caps"]),
          "net" => manifest["net"],
          "error" => manifest["__error"]
        }
      end
    end

    def parse_cameras
      camera_defconfigs.each do |absolute|
        relative = repo.relative(absolute)
        parts = relative.split("/")
        group = parts[1]
        directory = File.dirname(relative)
        name = File.basename(directory)
        text = repo.read(relative)
        own_symbols = parse_assignments(text)
        fragment_names = text.scan(/^#\s*FRAG:\s*(.+)$/).flat_map { |match| match[0].split }.uniq
        fragment_symbols = {}
        fragment_names.each do |fragment_name|
          fragment_symbols.merge!(fragments.dig(fragment_name, "symbols") || {})
        end
        effective = resolve_choices(fragment_symbols.merge(own_symbols))
        soc_model = effective["BR2_INGENIC_SOC_MODEL"] || effective["BR2_SIGMASTAR_SOC_MODEL"]
        soc = soc_models[soc_model]
        selected_symbols = package_closure(default_enabled_symbols.merge(effective))
        selected_packages = selected_symbols.filter_map { |symbol| @main_symbol_to_package[symbol] }.uniq.sort
        json_file = File.join(directory, "thingino.json")
        config = repo.exist?(json_file) ? parse_json(repo.read(json_file)) : nil
        key = "#{group}/#{name}"

        cameras[key] = {
          "id" => key,
          "name" => name,
          "group" => group,
          "dir" => directory,
          "defconfig" => relative,
          "defconfig_name" => File.basename(relative, "_defconfig"),
          "name_matches_dir" => File.basename(relative, "_defconfig") == name,
          "fragments" => fragment_names,
          "symbols" => effective,
          "own_symbols" => own_symbols,
          "flash_mb" => effective["FLASH_SIZE_MB"] || text[/^FLASH_SIZE_MB=(.+)$/, 1]&.strip,
          "soc_model" => soc_model,
          "soc_family" => soc && soc["family"],
          "soc_vendor" => soc && soc["vendor"],
          "sensors" => sensor_names(effective),
          "wifi_symbols" => wifi_symbols(effective),
          "selected_packages" => selected_packages,
          "has_json" => !config.nil?,
          "has_dts" => !repo.glob("#{directory}/*.dts").empty?,
          "json" => config
        }
      end

      repo.dirs("configs/cameras*/*").each do |absolute|
        relative = repo.relative(absolute)
        next if repo.glob("#{relative}/*_defconfig").any?

        profiles_without_defconfig << relative
      end
    end

    def parse_init_scripts
      paths = repo.glob("overlay/etc/init.d/*") +
              repo.glob("package/*/files/**/S[0-9]*") +
              repo.glob("package/*/files/**/K[0-9]*")
      paths.uniq.each do |absolute|
        relative = repo.relative(absolute)
        basename = File.basename(relative).sub(/\.in\z/, "")
        text = repo.read(relative)
        entry = {
          "path" => relative,
          "package" => relative.split("/")[0] == "package" ? relative.split("/")[1] : nil,
          "basename" => basename,
          "start" => text[/^\s*START\s*=\s*(\d+)/, 1],
          "stop" => text[/^\s*STOP\s*=\s*(\d+)/, 1],
          "provides" => text[/^\s*PROVIDES\s*=\s*(.+)$/, 1]&.split,
          "requires" => text[/^\s*REQUIRES\s*=\s*(.+)$/, 1]&.split,
          "use" => text[/^\s*USE\s*=\s*(.+)$/, 1]&.split
        }
        init_scripts << entry
        init_by_basename[basename] << entry
      end
    end

    def parse_plugins
      repo.glob("package/*/**/*.webui.json").each do |absolute|
        relative = repo.relative(absolute)
        package = relative.split("/")[1]
        manifest = parse_json(repo.read(relative))
        plugins << {
          "path" => relative,
          "package" => package,
          "name" => manifest["name"],
          "label" => manifest["label"],
          "api_version" => manifest["apiVersion"],
          "pages" => Array(manifest["pages"]),
          "cgi" => Array(manifest["cgi"]),
          "feature_flags" => manifest["featureFlags"] || {},
          "error" => manifest["__error"]
        }
      end
    end

    def attach_reverse_maps
      cameras.each_value do |camera|
        camera["selected_packages"].each { |package| cameras_by_package[package] << camera["id"] }
        cameras_by_family[camera["soc_family"]] << camera["id"] if camera["soc_family"]
        cameras_by_vendor[camera["soc_vendor"]] << camera["id"] if camera["soc_vendor"]
        camera["fragments"].each { |fragment| cameras_by_fragment[fragment] << camera["id"] }
        camera["wifi_symbols"].each { |symbol| cameras_by_wifi[symbol] << camera["id"] }
      end
      qemu_profiles.each_value do |profile|
        qemu_profiles_by_family[profile["family"]] << profile["name"] if profile["family"]
      end
    end

    def camera_defconfigs
      repo.glob("configs/cameras*/*/*_defconfig")
    end

    def config_files
      @config_files ||= (repo.glob("Config*") + repo.glob("package/**/Config*"))
                        .map { |path| repo.relative(path) }.uniq
    end

    def make_vars(files)
      vars = Hash.new { |hash, key| hash[key] = [] }
      files.each do |relative|
        text = repo.read(relative).gsub(/\\\n\s*/, " ")
        text.each_line do |line|
          next if line.lstrip.start_with?("#")

          match = line.match(/^\s*([A-Za-z0-9_]+)\s*(\+=|:=|\?=|=)\s*(.*?)\s*$/)
          vars[match[1]] << match[3] if match
        end
      end
      vars
    end

    def choose_prefix(name, vars)
      preferred = name.upcase.gsub(/[^A-Z0-9]/, "_")
      candidates = vars.keys.filter_map do |key|
        key[/\A(.+)_(?:VERSION|SITE|SITE_METHOD|DEPENDENCIES|LICENSE)\z/, 1]
      end.uniq
      candidates.include?(preferred) ? preferred : (candidates.first || preferred)
    end

    def value(vars, key)
      entry = vars[key]&.last
      entry&.strip
    end

    def remote_site?(site, site_method)
      return false if site.nil? || site.empty?
      return true if %w[git wget svn hg].include?(site_method)

      site.match?(%r{\A(?:https?|git|ssh)://})
    end

    def normalize_source(raw, from_relative)
      source = raw.strip.sub(/\A["']/, "").sub(/["']\z/, "")
      source = source.gsub(/\$\(BR2_EXTERNAL(?:_THINGINO_PATH)?\)|\$\{BR2_EXTERNAL(?:_THINGINO_PATH)?\}|\$BR2_EXTERNAL(?:_THINGINO_PATH)?/, "")
      return nil if source.empty? || source.include?("$")

      source = source.sub(%r{\A/+}, "")
      candidate = if source.start_with?("package/", "configs/", "soc/", "kernels/", "Config")
                    source
                  else
                    File.join(File.dirname(from_relative), source)
                  end
      Pathname.new(candidate).cleanpath.to_s
    end

    def package_for(relative)
      match = relative.match(%r{\Apackage/([^/]+)/})
      match && match[1]
    end

    def parse_make_call(text)
      args = []
      current = +""
      depth = 0
      text.each_char do |character|
        case character
        when "("
          depth += 1
          current << character
        when ")"
          break if depth.zero?

          depth -= 1
          current << character
        when ","
          if depth.zero?
            args << current
            current = +""
          else
            current << character
          end
        else
          current << character
        end
      end
      args << current
      args
    end

    def resolve_make_value(raw, vars, depth = 0)
      text = raw.to_s.strip
      if depth < 5 && (match = text.match(/\A\$\(([A-Z0-9_]+)\)\z/))
        resolved = vars[match[1]]&.last
        return resolve_make_value(resolved, vars, depth + 1) if resolved
      end
      text.sub(/\A"/, "").sub(/"\z/, "")
    end

    def infer_wifi_package(symbol)
      suffix = symbol.sub("BR2_PACKAGE_WIFI_", "").downcase.tr("_", "-")
      candidate = "wifi-#{suffix}"
      packages.key?(candidate) ? candidate : nil
    end

    def parse_assignments(text)
      symbols = {}
      text.each_line do |line|
        next if line.lstrip.start_with?("#")

        match = line.match(/^\s*(BR2_[A-Z0-9_]+)=(.*?)\s*$/)
        next unless match

        symbols[match[1]] = match[2].strip.sub(/\A"/, "").sub(/"\z/, "")
      end
      symbols
    end

    def package_closure(symbols)
      seen = Set.new
      queue = symbols.keys.dup
      until queue.empty?
        symbol = queue.shift
        next if seen.include?(symbol)

        seen << symbol
        Array(config_symbols.dig(symbol, "selects")).each do |selected|
          queue << selected unless seen.include?(selected)
        end
      end
      seen
    end

    def default_enabled_symbols
      @default_enabled_symbols ||= config_symbols.select { |_name, entry| entry["defaults"].include?("y") }
                                                  .keys.to_h { |symbol| [symbol, "y"] }
    end

    def resolve_choices(symbols)
      resolved = symbols.dup
      choices.each do |choice|
        next if choice["symbols"].any? { |symbol| resolved[symbol] == "y" }

        default = choice["default"]
        resolved[default] = "y" if default && choice["symbols"].include?(default)
      end
      resolved
    end

    def sensor_names(symbols)
      %w[1 2 3 4].filter_map do |number|
        value = symbols["BR2_SENSOR_#{number}_NAME"]
        next if value.nil? || value.empty? || value == "none"

        value
      end
    end

    def wifi_symbols(symbols)
      symbols.select do |name, value|
        next false unless value == "y"

        package = @main_symbol_to_package[name]
        wifi_drivers.key?(name) || (package && package.start_with?("wifi-"))
      end.keys.sort
    end

    def parse_json(text)
      JSON.parse(text)
    rescue JSON::ParserError => error
      { "__error" => error.message }
    end
  end
end
