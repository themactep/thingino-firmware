#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerate the 4.4.94 kernel patches and binary assets.
#
# The 4.4.94 kernel is built from the official kernel.org tarball plus a
# common patch and a per-SoC patch, mirroring the 3.10.14 layout. The four
# thingino-linux branches (t23, t31, t32, t41) share a large common delta
# against 4.4.94, so the common part is factored into one patch and only the
# per-branch remainder goes into each soc/ patch.
#
# What it does:
#   1. Checks out each branch at the commit recorded in SOURCES.
#   2. Restores upstream symlinks a branch may have dereferenced (the t31
#      vendor import expanded six arch/*/boot/dts/include/dt-bindings links).
#   3. Builds a "common" tree from the file-level intersection of all four
#      branches: a file is common only if every branch carries it byte for
#      byte. Everything else stays per-SoC.
#   4. Writes 0001-4.4.94-common.patch (base -> common) and
#      soc/<soc>/0001-4.4.94-<soc>.patch (common -> branch), stripping binary
#      hunks that GNU patch cannot apply.
#   5. Re-applies the patches and collects whatever is still missing
#      (binaries, empty files, new symlinks) into
#      package/linux/files/4.4.94/, sharing identical files under common/.
#
# Usage:
#   scripts/generate_kernel_4.4.94_patches.rb [--dl DIR] [--keep] [--dry-run]
#
# --dl DIR    directory holding linux/linux-4.4.94.tar.xz (defaults to
#             $BR2_DL_DIR, then <repo>/dl; downloads from kernel.org if absent)
# --keep      keep the temporary work tree and print its path
# --dry-run   generate into the temp tree only; do not touch the repo

require 'digest'
require 'fileutils'
require 'find'
require 'open3'
require 'tmpdir'

REPO = File.expand_path('..', __dir__)
REMOTE = 'https://github.com/gtxaspec/thingino-linux'
VERSION = '4.4.94'
TARBALL = "linux-#{VERSION}.tar.xz"
TARBALL_URL = "https://cdn.kernel.org/pub/linux/kernel/v4.x/#{TARBALL}"
PATCH_DIR = File.join(REPO, 'package/all-patches/linux', VERSION)
ASSET_DIR = File.join(REPO, 'package/linux/files', VERSION)
SOURCES = File.join(PATCH_DIR, 'SOURCES')

def run(*cmd, **opts)
  output, status = Open3.capture2e(*cmd, **opts)
  raise "command failed: #{cmd.join(' ')}\n#{output}" unless status.success?

  output
end

def cp_a(src, dst)
  run('cp', '-a', '--remove-destination', src, dst)
end

def sources
  File.readlines(SOURCES).filter_map do |line|
    next if line.start_with?('#')

    soc, branch, commit = line.split
    next unless soc && branch && commit

    [soc, branch, commit]
  end
end

def find_tarball(dl)
  candidates = []
  candidates << File.join(ENV['BR2_DL_DIR'], 'linux', TARBALL) if ENV['BR2_DL_DIR']
  candidates << File.join(dl, 'linux', TARBALL) if dl
  candidates << File.join(REPO, 'dl', 'linux', TARBALL)
  candidates.find { |p| File.file?(p) }
end

# SHA-256 of a regular file, or the link target for a symlink. Find does not
# descend symlinks, so arch/*/boot/dts/include/dt-bindings links are recorded
# once as links rather than as a copy of every binding header.
def signatures(dir)
  sigs = {}
  Find.find(dir) do |path|
    next if path == dir

    rel = path.delete_prefix(dir + '/')
    sigs[rel] =
      if File.symlink?(path) then "L#{File.readlink(path)}"
      elsif File.file?(path) then "F#{Digest::SHA256.file(path).hexdigest}"
      end
  end
  sigs
end

# A branch that dereferenced an upstream symlink (copied the target in place)
# would otherwise emit thousands of spurious file creations. Restore the
# upstream link: it resolves to the same content.
def restore_upstream_symlinks(base, dir)
  restored = 0
  Find.find(base) do |src|
    next unless File.symlink?(src)

    rel = src.delete_prefix(base + '/')
    dst = File.join(dir, rel)
    next if File.symlink?(dst)
    next unless File.exist?(dst)

    FileUtils.rm_rf(dst)
    FileUtils.mkdir_p(File.dirname(dst))
    File.symlink(File.readlink(src), dst)
    restored += 1
  end
  restored
end

def build_common(base_dir, tree_dirs, common)
  base = signatures(base_dir)
  sigs = tree_dirs.transform_values { |d| signatures(d) }

  set = {}
  delete = []
  (base.keys + sigs.values.flat_map(&:keys)).uniq.each do |rel|
    entries = sigs.values.map { |s| s[rel] }
    if entries.none?(&:nil?) && entries.uniq.size == 1
      set[rel] = entries.first unless base[rel] == entries.first
    elsif !base[rel].nil? && entries.all?(&:nil?)
      delete << rel
    end
  end

  FileUtils.rm_rf(common)
  FileUtils.cp_r(base_dir, common)
  first = tree_dirs.values.first
  set.each_key do |rel|
    dst = File.join(common, rel)
    FileUtils.mkdir_p(File.dirname(dst))
    cp_a(File.join(first, rel), dst)
  end
  delete.each { |rel| FileUtils.rm_rf(File.join(common, rel)) }

  [set.size, delete.size]
end

def diff_patch(from, to, out)
  # Run with relative paths from their common parent so the patch headers are
  # <dir>/<path>; patch -p1 then strips exactly one component.
  dir = File.dirname(from)
  # --no-dereference keeps diff from walking arch/*/boot/dts/include/
  # dt-bindings links, which would duplicate every binding header.
  FileUtils.mkdir_p(File.dirname(out))
  system('diff', '-ruN', '--no-dereference', '--exclude=.git',
         File.basename(from), File.basename(to),
         out: File.absolute_path(out), err: File::NULL, chdir: dir)
  # diff exits 2 when it cannot stat a newly added symlink, which GNU patch
  # could not create anyway; such links are restored from
  # package/linux/files/ instead. verify below proves nothing else was lost.
  unless [0, 1, 2].include?($?.exitstatus)
    raise "diff failed for #{from} -> #{to}"
  end

  # Binary hunks are likewise carried by package/linux/files/. Drop both the
  # "Binary files" note and the diff(1) header that introduced it, or patch
  # would trip over a header with no ---/+++ body.
  kept = []
  File.readlines(out).each do |line|
    if line.start_with?('Binary files ')
      kept.pop if kept.last&.start_with?('diff -ruN')
      next
    end
    kept << line
  end
  File.write(out, kept.join)
end

def apply(dir, patch)
  run('patch', '-p1', '-s', '--batch', '--forward', '-d', dir,
      stdin_data: File.read(patch))
end

# Anything the text patches cannot reproduce (binaries, empty files, symlinks)
# is copied out of the branch tree. Directories are not copied: they come into
# being with the files below them. recon is a scratch copy of the base tree
# with the patches applied; out_dir receives only the missing entries.
def collect_assets(base_dir, tree, patches, recon, out_dir)
  FileUtils.rm_rf(recon)
  FileUtils.cp_r(base_dir, recon)
  patches.each { |p| apply(recon, p) }

  Find.find(tree).sort.each do |path|
    next if path == tree
    next unless File.file?(path) || File.symlink?(path)

    rel = path.delete_prefix(tree + '/')
    dst = File.join(recon, rel)
    next if File.symlink?(dst) && File.readlink(dst) == File.readlink(path)
    next if File.file?(dst) && !File.symlink?(path) && FileUtils.cmp(path, dst)

    target = File.join(out_dir, rel)
    FileUtils.mkdir_p(File.dirname(target))
    cp_a(path, target)
  end
end

def generate_patches(base, common, trees, staging)
  FileUtils.mkdir_p(staging)
  common_patch = File.join(staging, "0001-#{VERSION}-common.patch")
  diff_patch(base, common, common_patch)

  patches = {}
  trees.each_key do |soc|
    patches[soc] = File.join(staging, soc, "0001-#{VERSION}-#{soc}.patch")
    diff_patch(common, trees[soc], patches[soc])
  end
  [common_patch, patches]
end

def install_assets(work, base, trees, common_patch, patches, asset_root)
  FileUtils.rm_rf(asset_root)
  FileUtils.mkdir_p(File.join(asset_root, 'common'))

  shared = nil
  trees.each_key do |soc|
    out_dir = File.join(asset_root, soc)
    recon = File.join(work, "recon-#{soc}")
    collect_assets(base, trees[soc], [common_patch, patches[soc]], recon, out_dir)
    FileUtils.rm_rf(recon)
    files = Find.find(out_dir).select { |p| File.file?(p) && !File.symlink?(p) }
                .map { |p| p.delete_prefix(out_dir + '/') }
    shared = shared.nil? ? files : shared & files
  end

  (shared || []).each do |rel|
    srcs = trees.keys.map { |soc| File.join(asset_root, soc, rel) }
    next unless srcs.map { |p| Digest::SHA256.file(p).hexdigest }.uniq.size == 1

    dst = File.join(asset_root, 'common', rel)
    FileUtils.mkdir_p(File.dirname(dst))
    FileUtils.mv(srcs.first, dst)
    srcs.drop(1).each { |p| FileUtils.rm_f(p) }
  end
end

def verify(base_dir, trees, common_patch, patches, asset_root)
  trees.each do |soc, tree|
    dir = File.join(File.dirname(base_dir), "verify-#{soc}")
    FileUtils.rm_rf(dir)
    FileUtils.cp_r(base_dir, dir)
    apply(dir, common_patch)
    apply(dir, patches[soc])
    cp_a(File.join(asset_root, 'common') + '/.', dir)
    soc_assets = File.join(asset_root, soc)
    cp_a(soc_assets + '/.', dir) if File.directory?(soc_assets)

    out = File.join(File.dirname(base_dir), "verify-#{soc}.diff")
    system('diff', '-rq', '--no-dereference', '--exclude=.git', dir, tree,
           out: out, err: File::NULL)
    # 0002/0003 fix mkcompile_h/unifdef.c and are applied separately by the
    # build; the upstream doc PDFs are binary deletions left in place.
    bad = File.readlines(out).reject { |l| l =~ /mkcompile_h|unifdef\.c|\.pdf/ }
    raise "verification failed for #{soc}:\n#{bad.join}" unless bad.empty?

    FileUtils.rm_rf([dir, out])
    puts "==> verified #{soc}"
  end
end

def main
  dl = nil
  keep = dry_run = false
  args = ARGV.dup
  until args.empty?
    case (arg = args.shift)
    when '--dl' then dl = args.shift
    when '--keep' then keep = true
    when '--dry-run' then dry_run = true
    when '-h', '--help'
      puts File.readlines(__FILE__).grep(/^# /)
               .reject { |l| l.include?('frozen_string_literal') }
               .map { |l| l.sub(/^# ?/, '') }
      return
    else abort "unknown option: #{arg}"
    end
  end

  tarball = find_tarball(dl)
  abort "missing #{TARBALL}: pass --dl or set BR2_DL_DIR" unless tarball

  work = Dir.mktmpdir('k494-')
  puts "work dir: #{work}"
  begin
    puts '==> fetching thingino-linux'
    clone = File.join(work, 'clone')
    run('git', 'clone', '--quiet', '--filter=blob:none', '--no-checkout',
        REMOTE, clone)

    trees = {}
    sources.each do |soc, _branch, commit|
      dir = File.join(work, "tree-#{soc}")
      run('git', '-C', clone, 'worktree', 'add', '--detach', dir, commit)
      FileUtils.rm_f(File.join(dir, '.git'))
      trees[soc] = dir
    end

    puts "==> extracting #{tarball}"
    base = File.join(work, "linux-#{VERSION}")
    run('tar', '-xf', tarball, '-C', work)

    normalize = trees.sum { |_soc, dir| restore_upstream_symlinks(base, dir) }
    puts "==> normalized #{normalize} dereferenced symlinks"

    common = File.join(work, 'common')
    files, deletes = build_common(base, trees, common)
    puts "==> common: #{files} files set, #{deletes} deleted"

    staging = File.join(work, 'out')
    common_patch, patches = generate_patches(base, common, trees, staging)

    puts '==> staging assets'
    staged_assets = File.join(work, 'assets')
    install_assets(work, base, trees, common_patch, patches, staged_assets)

    puts '==> verifying'
    verify(base, trees, common_patch, patches, staged_assets)

    if dry_run
      puts "==> dry run: patches left in #{staging}"
      return
    end

    puts '==> installing patches'
    FileUtils.mkdir_p(PATCH_DIR)
    FileUtils.cp(common_patch, PATCH_DIR)
    patches.each do |soc, patch|
      dest = File.join(PATCH_DIR, 'soc', soc)
      FileUtils.mkdir_p(dest)
      FileUtils.cp(patch, dest)
    end

    puts '==> installing assets'
    FileUtils.rm_rf(ASSET_DIR)
    FileUtils.cp_r(staged_assets, ASSET_DIR)

    puts '==> done'
    puts "    patches: #{PATCH_DIR}"
    puts "    assets:  #{ASSET_DIR}"
  ensure
    if keep
      puts "kept work dir: #{work}"
    else
      FileUtils.rm_rf(work)
    end
  end
end

main if $PROGRAM_NAME == __FILE__
