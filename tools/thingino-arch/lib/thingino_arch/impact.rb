require "set"

module ThinginoArch
  class Impact
    attr_reader :index, :changed_files, :entities, :affected_cameras, :global

    def initialize(index, changed_files)
      @index = index
      @changed_files = changed_files
      @entities = {
        "packages" => Set.new,
        "cameras" => Set.new,
        "fragments" => Set.new,
        "soc_families" => Set.new,
        "kernels" => Set.new,
        "plugins" => Set.new,
        "init_scripts" => Set.new,
        "tooling" => Set.new,
        "other" => Set.new
      }
      @camera_reasons = Hash.new { |hash, key| hash[key] = Set.new }
      @global = false
      analyze
      @affected_cameras = @camera_reasons.keys.sort.map do |id|
        camera = index.cameras[id]
        {
          "id" => id,
          "group" => camera["group"],
          "name" => camera["name"],
          "soc_family" => camera["soc_family"],
          "sensors" => camera["sensors"],
          "wifi" => camera["wifi_symbols"],
          "reasons" => @camera_reasons[id].to_a.sort
        }
      end
    end

    def to_h
      {
        "changed_files" => changed_files,
        "entities" => entities.transform_values { |value| value.to_a.sort },
        "affected_cameras" => affected_cameras,
        "counts" => {
          "changed_files" => changed_files.size,
          "affected_cameras" => affected_cameras.size,
          "packages" => entities["packages"].size,
          "fragments" => entities["fragments"].size,
          "soc_families" => entities["soc_families"].size,
          "plugins" => entities["plugins"].size,
          "init_scripts" => entities["init_scripts"].size
        },
        "global" => global
      }
    end

    def summary
      lines = []
      lines << "Changed files: #{changed_files.size}"
      lines << "Affected camera profiles: #{affected_cameras.size}"
      lines << "Packages: #{entities['packages'].to_a.sort.join(', ')}" unless entities["packages"].empty?
      lines << "Fragments: #{entities['fragments'].to_a.sort.join(', ')}" unless entities["fragments"].empty?
      lines << "SoC families: #{entities['soc_families'].to_a.sort.join(', ')}" unless entities["soc_families"].empty?
      lines << "Plugins: #{entities['plugins'].to_a.sort.join(', ')}" unless entities["plugins"].empty?
      lines << "Init scripts: #{entities['init_scripts'].to_a.sort.join(', ')}" unless entities["init_scripts"].empty?
      lines << "Tooling-only change" if affected_cameras.empty? && !entities["tooling"].empty?
      lines.join("\n")
    end

    private

    def analyze
      changed_files.each do |path|
        case path
        when %r{\Apackage/all-patches/} then add_global("patch-store")
        when %r{\Apackage/([^/]+)/}
          add_package(Regexp.last_match(1), path)
        when %r{\Aconfigs/cameras[^/]*/([^/]+)/}
          add_camera(Regexp.last_match(1), path)
        when %r{\Aconfigs/fragments/(.+)\z}
          add_fragment(Regexp.last_match(1), path)
        when %r{\Asoc/([^/]+)/([^/]+)\.mk\z}
          add_soc(Regexp.last_match(1), path)
        when %r{\Akernels/([^/]+)\.mk\z}
          add_kernel(Regexp.last_match(1), path)
        when %r{\Aoverlay/} then add_global("overlay")
        when %r{\A(?:Makefile[^/]*|thingino\.mk|external\.mk|Config\.(?:in|soc\.in|sensor\.in|host)|Config\.in\.host)\z}
          add_global("build-system")
        when %r{\Aconfigs/} then add_global("camera-config")
        when %r{\A(?:scripts|docs|\.github|\.githooks)/} then entities["tooling"] << path
        else entities["other"] << path
        end
      end
    end

    def add_package(name, path)
      entities["packages"] << name
      index.cameras_by_package[name].each { |id| @camera_reasons[id] << "package:#{name}" }
      index.plugins.select { |plugin| plugin["package"] == name }.each do |plugin|
        entities["plugins"] << plugin["name"]
      end
      index.init_scripts.select { |script| script["package"] == name }.each do |script|
        entities["init_scripts"] << script["basename"]
      end
      add_global("package-all") if name == "all-patches"
      entities["other"] << path if !index.packages.key?(name) && !path.start_with?("package/all-patches/")
    end

    def add_camera(name, path)
      camera = index.cameras.values.find { |entry| entry["dir"].end_with?("/#{name}") && path.start_with?(entry["dir"]) }
      if camera
        entities["cameras"] << camera["id"]
        @camera_reasons[camera["id"]] << "camera:#{camera['id']}"
      else
        add_global("camera-config")
      end
    end

    def add_fragment(name, path)
      fragment = File.basename(name, ".fragment")
      if index.fragments.key?(fragment)
        cameras = index.cameras_by_fragment[fragment]
        if cameras.empty?
          add_global("fragment:#{fragment}")
        else
          entities["fragments"] << fragment
          cameras.each { |id| @camera_reasons[id] << "fragment:#{fragment}" }
        end
      else
        add_global("fragment:#{path}")
      end
    end

    def add_soc(vendor, path)
      family = index.soc_families.values.find { |entry| entry["file"] == path }
      if family
        entities["soc_families"] << family["family"]
        index.cameras_by_family[family["family"]].each { |id| @camera_reasons[id] << "soc:#{family['family']}" }
      else
        entities["soc_families"] << File.basename(path, ".mk")
        index.cameras_by_vendor[vendor].each { |id| @camera_reasons[id] << "soc-vendor:#{vendor}" }
      end
    end

    def add_kernel(vendor, path)
      entities["kernels"] << vendor
      index.cameras_by_vendor[vendor].each { |id| @camera_reasons[id] << "kernel:#{vendor}" }
      add_global("kernel:#{path}") if index.cameras_by_vendor[vendor].empty?
    end

    def add_global(reason)
      @global = true
      index.cameras.each_key { |id| @camera_reasons[id] << reason }
    end
  end
end
