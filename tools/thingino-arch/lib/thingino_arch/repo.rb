require "open3"
require "pathname"

module ThinginoArch
  class Repo
    attr_reader :root

    def initialize(root)
      @root = File.expand_path(root)
      unless File.file?(File.join(@root, "thingino.mk")) && File.directory?(File.join(@root, "package"))
        raise ArgumentError, "not a Thingino firmware tree: #{@root}"
      end
    end

    def path(relative)
      File.join(root, relative)
    end

    def exist?(relative)
      File.exist?(path(relative))
    end

    def read(relative)
      File.read(path(relative), encoding: "UTF-8")
    end

    def glob(pattern)
      Dir.glob(File.join(root, pattern), File::FNM_DOTMATCH)
         .reject { |entry| [".", ".."].include?(File.basename(entry)) }
         .select { |entry| File.file?(entry) }
         .map { |entry| File.expand_path(entry) }
         .uniq
    end

    def dirs(pattern)
      Dir.glob(File.join(root, pattern), File::FNM_DOTMATCH)
         .reject { |entry| [".", ".."].include?(File.basename(entry)) }
         .select { |entry| File.directory?(entry) }
         .map { |entry| File.expand_path(entry) }
         .uniq
    end

    def relative(absolute)
      Pathname.new(absolute).relative_path_from(Pathname.new(root)).to_s
    end

    def git(*args)
      stdout, stderr, status = Open3.capture3("git", "-C", root, *args)
      raise "git #{args.join(' ')} failed: #{stderr.strip}" unless status.success?

      stdout
    end

    def head
      git("rev-parse", "HEAD").strip
    rescue StandardError
      nil
    end

    def changed_files(from, to)
      git("diff", "--name-only", "--diff-filter=ACMRD", "#{from}..#{to}")
        .lines.map(&:strip).reject(&:empty?)
    end

    def diff_text(from, to)
      git("diff", "--no-ext-diff", "--no-textconv", "--no-color", "#{from}..#{to}")
    end

    def diff_stat(from, to)
      git("diff", "--stat", "--no-ext-diff", "--no-color", "#{from}..#{to}")
    end

    def github_slug
      url = git("remote", "get-url", "origin").strip
      match = url.match(%r{github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?/?\z})
      match ? "#{match[1]}/#{match[2]}" : nil
    rescue StandardError
      nil
    end
  end
end
